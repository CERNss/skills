"""
run_research.py — cache-first EasyNero pipeline script.

Usage:
    python skills/research-graph/scripts/run_research.py "<paper title or topic>"
    python skills/research-graph/scripts/run_research.py "<paper title or topic>" --paper-id <id>

When --paper-id is supplied (e.g. passed from paper-search skill), the Semantic
Scholar lookup is skipped entirely. Outputs a single JSON object to stdout.
All log lines go to stderr. Exit code 0 on success, 1 on failure.
"""

import argparse
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent.parent
sys.path.insert(0, str(ROOT))

from src.config import config
from src.agents.survey_agent import generate_survey_report
from src.tools.semantic_scholar import search_papers
from src.tools.connected_papers import get_paper_graph_data
from src.utils.graph_processing import analyze_connected_papers_graph
from src.utils.storage import (
    create_session_id,
    read_json,
    save_session_artifacts,
)


def _find_cached_session(paper_id: str):
    """Return the most recent session metadata dict matching paper_id, or None."""
    session_dir = config.session_dir
    if not session_dir.exists():
        return None
    for path in sorted(session_dir.glob("*.json"), reverse=True):
        try:
            meta = read_json(path)
            if meta.get("selectedPaper", {}).get("paperId") == paper_id:
                return meta
        except Exception:
            continue
    return None


def main(query: str, paper_id: str = None) -> dict:
    if paper_id:
        print(f"[run_research] paper_id supplied directly — skipping Semantic Scholar lookup", file=sys.stderr)
        selected_paper = {"paperId": paper_id, "title": query}
    else:
        print(f"[run_research] Searching Semantic Scholar for: {query}", file=sys.stderr)
        papers = search_papers(query, k=5)
        if not papers:
            raise RuntimeError(f"No papers found on Semantic Scholar for query: {query!r}")
        selected_paper = papers[0]
        paper_id = selected_paper["paperId"]
        print(f"[run_research] Top result: {selected_paper.get('title')} ({selected_paper.get('year')})", file=sys.stderr)

    # Cache check
    cached_session = _find_cached_session(paper_id)
    if cached_session:
        print(f"[run_research] Cache hit — loading graph from {cached_session['graphPath']}", file=sys.stderr)
        graph_data = read_json(cached_session["graphPath"])
        cache_hit = True
    else:
        print(f"[run_research] Cache miss — fetching Connected Papers graph (1 CP credit)", file=sys.stderr)
        graph_data = get_paper_graph_data(
            paper_id,
            fresh_only=config.connected_papers_fresh_only,
            verbose=config.connected_papers_verbose,
        )
        cache_hit = False

    print(f"[run_research] Analysing graph ({graph_data.get('nodesCount', '?')} nodes)...", file=sys.stderr)
    analysis = analyze_connected_papers_graph(
        selected_paper=selected_paper,
        graph_data=graph_data,
        top_n=config.graph_top_n,
        selection_strategy=config.graph_search_strategy,
        wide_depth_cap=config.graph_wide_depth_cap,
        deep_depth_cap=config.deep_depth_cap,
        prior_derivative_source=config.prior_derivative_source,
    )

    print(f"[run_research] Generating survey report with {config.model_name}...", file=sys.stderr)
    report_markdown = generate_survey_report(
        query=query,
        selected_paper=analysis["seedPaper"],
        analysis=analysis,
    )

    new_session_id = create_session_id(query, paper_id)
    paths = save_session_artifacts(
        session_id=new_session_id,
        query=query,
        selected_paper=analysis["seedPaper"],
        graph_data=graph_data,
        report_markdown=report_markdown,
        analysis=analysis,
    )

    result = {
        "session_id": new_session_id,
        "paper_id": paper_id,
        "title": analysis["seedPaper"].get("title"),
        "year": analysis["seedPaper"].get("year"),
        "cache_hit": cache_hit,
        "report_path": paths["report_path"],
        "graph_path": paths["graph_path"],
        "report_markdown": report_markdown,
        "prior_works": [
            {"title": p.get("title"), "year": p.get("year")}
            for p in analysis.get("priorWorks", [])[:10]
            if p.get("title")
        ],
        "derivative_works": [
            {"title": p.get("title"), "year": p.get("year")}
            for p in analysis.get("derivativeWorks", [])[:10]
            if p.get("title")
        ],
        "top_papers": [
            {"title": p.get("title"), "year": p.get("year"), "pathLength": p.get("pathLength")}
            for p in analysis.get("topPapers", [])[:10]
            if p.get("title")
        ],
        "open_questions": analysis.get("openQuestions", []),
    }
    print(f"[run_research] Done. session_id={new_session_id} cache_hit={cache_hit}", file=sys.stderr)
    return result


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="EasyNero research pipeline")
    parser.add_argument("query", help="Paper title or topic to research")
    parser.add_argument("--paper-id", dest="paper_id", default=None,
                        help="Skip Semantic Scholar lookup and use this paper_id directly")
    args = parser.parse_args()
    try:
        output = main(args.query, paper_id=args.paper_id)
        print(json.dumps(output, ensure_ascii=False, indent=2))
    except Exception as exc:
        print(json.dumps({"error": str(exc)}), file=sys.stdout)
        print(f"[run_research] ERROR: {exc}", file=sys.stderr)
        sys.exit(1)
