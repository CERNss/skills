---
name: paper-search
description: This skill should be used when the user asks to "find papers on X", "search for papers about X", "recommend papers on X", "I need papers about X", "what should I read about X", "can you search me a paper about X", or gives a fuzzy topic without a specific paper title in mind. Returns ranked Semantic Scholar results with paper_id, citation count, venue, and abstract snippet. Designed to feed into the research-graph skill when the user selects a paper.
metadata:
  version: 0.1.0
---

# Paper Search Skill

Searches Semantic Scholar for academic papers matching a topic or query. Returns ranked candidates with quality signals so the user can pick the most relevant one. Feeds directly into `research-graph` — no redundant lookup needed.

## Workflow

### Step 1 — Extract query

Extract the topic or query from the user's message. If the user is vague (e.g. "something about agents"), ask one clarifying question to narrow it: "Are you looking for a survey, a specific technique, or the latest research?" — then proceed.

### Step 2 — Run the search

```bash
python skills/paper-search/scripts/search_papers.py "<query>" [k]
```

`k` defaults to 8. Increase to 12 if the user wants a broader sweep. Output goes to stdout as JSON.

### Step 3 — Present results

Present a ranked table sorted by citation count (highest = most established). For each paper show:
- Number (for easy selection)
- Title
- Year | Venue
- Authors (up to 3)
- Citation count
- TL;DR or abstract snippet if available

### Step 4 — Invite selection and handoff

End with:

> "Pick a number to go deeper, or tell me which one looks most relevant. Once you pick one I can do a full graph research on it — building the citation graph, identifying prior and derivative works, and generating a survey report."

### Step 5 — Handoff to research-graph

When the user picks a paper (by number or title), pass the `paper_id` directly to `run_research.py` to skip the redundant Semantic Scholar lookup:

```bash
python skills/research-graph/scripts/run_research.py "<title>" --paper-id <paperId>
```

This triggers the full research-graph pipeline without spending an extra API call on paper lookup.
