"""
answer_question.py — Q&A grounded in a saved session's artifacts.

Usage:
    python skills/research-graph/scripts/answer_question.py "<session_id>" "<question>"

Outputs the answer text to stdout. All log lines go to stderr.
Exit code 0 on success, 1 on failure.
"""

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent.parent
sys.path.insert(0, str(ROOT))

from src.config import config
from src.agents.survey_agent import answer_question
from src.utils.retrieval import format_context_blocks, retrieve_context
from src.utils.storage import read_json, read_markdown


def main(session_id: str, question: str) -> str:
    session_path = config.session_dir / f"{session_id}.json"
    if not session_path.exists():
        raise FileNotFoundError(
            f"Session not found: {session_id}\n"
            f"Expected file: {session_path}\n"
            "Run run_research.py first to generate a session."
        )

    print(f"[answer_question] Loading session {session_id}", file=sys.stderr)
    session = read_json(session_path)

    report_markdown = read_markdown(session["reportPath"])
    graph_data = read_json(session["graphPath"])
    analysis = session.get("analysis", {})

    print(f"[answer_question] Retrieving context for: {question!r}", file=sys.stderr)
    retrieved = retrieve_context(
        question=question,
        report_markdown=report_markdown,
        graph_data=graph_data,
        analysis=analysis,
        top_k=config.qa_retrieval_k,
    )
    context_blocks = format_context_blocks(retrieved)

    print(f"[answer_question] Calling LLM ({config.model_name})...", file=sys.stderr)
    return answer_question(
        question=question,
        report_markdown=report_markdown,
        context_blocks=context_blocks,
    )


if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("Usage: answer_question.py <session_id> <question>")
        sys.exit(1)
    session_id = sys.argv[1]
    question = sys.argv[2]
    try:
        answer = main(session_id, question)
        print(answer)
    except Exception as exc:
        print(f"Error: {exc}", file=sys.stderr)
        sys.exit(1)
