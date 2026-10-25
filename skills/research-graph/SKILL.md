---
name: research-graph
description: >-
  This skill should be used when the user asks to "do graph research on this paper",
  "do graph research on paper X", "research this paper with the graph tool",
  "generate a graph survey for paper X", "build a citation graph for X", or asks
  follow-up questions about a paper that was previously researched using this skill.
  Activates the EasyNero pipeline: Semantic Scholar lookup → Connected Papers graph
  → DFS/BFS analysis → LLM survey report with prior works, derivative works, and open
  questions.
metadata:
  version: 0.1.0
---

# Research Graph Skill

Runs the EasyNero academic research pipeline for a given paper. Checks local cache first; only calls Connected Papers if the paper has not been fetched before (1 credit per new paper).

## Workflow

### Step 1 — Identify the paper

If the user provided a specific title, use it directly.

If the user only has a topic or is unsure which paper to use, **do not silently search on your own** — the `paper-search` skill handles discovery. Tell the user: *"I can search for candidates first — just ask me to find papers on [topic]."*

If the `paper-search` skill already ran and the user picked a paper, you will have both a `title` and a `paper_id`. Use both.

### Step 2 — Run the research pipeline

With paper_id known (from paper-search):
```bash
python skills/research-graph/scripts/run_research.py "<title>" --paper-id <paper_id>
```

Without paper_id (title only):
```bash
python skills/research-graph/scripts/run_research.py "<title>"
```

Parse the JSON output. Key fields:
- `session_id` — store this, required for all follow-up Q&A
- `cache_hit` — true if graph was loaded from local cache (no CP credit used)
- `title`, `year` — confirmed paper identity
- `report_markdown` — full LLM-generated survey
- `prior_works` — foundational predecessors
- `derivative_works` — papers building on this work
- `top_papers` — closest graph neighbors by path distance
- `open_questions` — unresolved questions the graph analysis surfaced

If the script exits non-zero, read stderr and report the error. Common causes: Clash proxy not running (503), Connected Papers quota exhausted, paper not found on Semantic Scholar.

### Step 3 — Present results

Present in this order:

1. **Paper confirmed** — title, year, venue. Note: *"Graph loaded from cache — no CP credit used"* or *"Graph fetched live — 1 CP credit used."*

2. **Prior works** (top 5) — foundational papers the field builds on. Format: `[year] Title`

3. **Derivative works** (top 5) — cutting-edge papers building on this work. Format: `[year] Title`

4. **Survey report** — print the full `report_markdown`

5. **Open questions** — explicitly surface the `open_questions` list from the JSON output. Present them as a numbered list and say: *"These are the open questions the graph analysis surfaced. Which one would you like to explore?"*

### Step 4 — Store session_id

Keep `session_id` in the conversation context. Every follow-up question needs it.

### Step 5 — Follow-up questions

When the user asks a follow-up question, first classify it:

**Specific / factual** (e.g. "which year was paper X published?", "how many papers are in the graph?", "who are the authors?"):
→ Run `answer_question.py` and return the output directly. Do not add to it.

```bash
python skills/research-graph/scripts/answer_question.py "<session_id>" "<question>"
```

**Wide / conceptual** (e.g. "what are the main unsolved problems?", "how does this compare to X?", "what direction is the field going?"):
→ Run `answer_question.py` for grounding, then synthesize with your own general knowledge to give a fuller answer. Always be explicit about what comes from the retrieved graph vs your general knowledge. Example: *"From the graph: [retrieved content]. More broadly: [your synthesis]."*

## Additional Resources

- **`references/workflow.md`** — internals of the analysis pipeline, config knobs, session schema, error handling
