"""
search_papers.py — Semantic Scholar paper discovery script.

Usage:
    python skills/paper-search/scripts/search_papers.py "<query>" [k]

Outputs a JSON array to stdout sorted by citation count descending.
All log lines go to stderr.
Exit code 0 on success, 1 on failure.
"""

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent.parent
sys.path.insert(0, str(ROOT))

from src.tools.semantic_scholar import search_papers


def main(query: str, k: int = 8) -> list:
    print(f"[paper-search] Searching Semantic Scholar: {query!r} (k={k})", file=sys.stderr)
    papers = search_papers(query, k=k)
    if not papers:
        print(f"[paper-search] No results found for: {query!r}", file=sys.stderr)
        return []

    results = []
    for paper in papers:
        authors = [a["name"] for a in paper.get("authors", [])[:3] if a.get("name")]
        abstract = paper.get("abstract") or ""
        results.append({
            "paperId": paper.get("paperId"),
            "title": paper.get("title"),
            "year": paper.get("year"),
            "venue": paper.get("venue") or "preprint",
            "citationCount": paper.get("citationCount") or 0,
            "authors": authors,
            "tldr": paper.get("tldr"),
            "abstract_snippet": abstract[:200] + "..." if len(abstract) > 200 else abstract,
            "isOpenAccess": paper.get("isOpenAccess"),
            "url": paper.get("url"),
        })

    results.sort(key=lambda p: p["citationCount"], reverse=True)
    print(f"[paper-search] Found {len(results)} results, returning sorted by citations.", file=sys.stderr)
    return results


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(json.dumps({"error": "Usage: search_papers.py <query> [k]"}))
        sys.exit(1)
    query = sys.argv[1]
    k = int(sys.argv[2]) if len(sys.argv) > 2 else 8
    try:
        output = main(query, k)
        print(json.dumps(output, ensure_ascii=False, indent=2))
    except Exception as exc:
        print(json.dumps({"error": str(exc)}))
        print(f"[paper-search] ERROR: {exc}", file=sys.stderr)
        sys.exit(1)
