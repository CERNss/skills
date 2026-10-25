# Research Graph Skill — Workflow Reference

## Pipeline overview

```
User message
  └─ SKILL.md (Claude orchestrates)
       ├─ run_research.py
       │    ├─ search_papers()           src/tools/semantic_scholar.py
       │    ├─ cache check               data/sessions/*.json
       │    ├─ get_paper_graph_data()    src/tools/connected_papers.py  [only on cache miss]
       │    ├─ analyze_connected_papers_graph()  src/utils/graph_processing.py
       │    ├─ generate_survey_report()  src/agents/survey_agent.py
       │    └─ save_session_artifacts()  src/utils/storage.py
       └─ answer_question.py  [for follow-up Q&A]
            ├─ retrieve_context()        src/utils/retrieval.py
            └─ answer_question()         src/agents/survey_agent.py
```

## Config knobs (set in .env or as env vars)

| Variable | Default | Effect |
|---|---|---|
| `MODEL_NAME` | `gpt-4o-mini` | LLM used for survey generation and Q&A |
| `PRIOR_DERIVATIVE_SOURCE` | `connected_papers` | `connected_papers` = use CP's commonReferences/commonCitations; `graph_traversal` = derive from graph nodes by year |
| `DEEP_DEPTH_CAP` | _(none)_ | Max path length for DFS paper selection (e.g. `5`) |
| `GRAPH_TOP_N` | `12` | Max papers selected as topPapers |
| `GRAPH_SEARCH_STRATEGY` | `deep_first` | `deep_first` or `wide_first` |
| `CONNECTED_PAPERS_FRESH_ONLY` | `false` | Force CP to skip its own cache |

## PRIOR_DERIVATIVE_SOURCE explained

- **`connected_papers`** (default): `priorWorks` = CP's `commonReferences` (papers co-cited across the graph — often broad foundational works outside the graph). `derivativeWorks` = CP's `commonCitations` (papers that cite the graph's papers — often outside the graph nodes).
- **`graph_traversal`**: `priorWorks` = graph nodes where `year < seed_year`, sorted by pathLength. `derivativeWorks` = graph nodes where `year > seed_year`, sorted by pathLength. Only uses papers actually in the retrieved graph.

Both `cpPriorWorks` and `cpDerivativeWorks` are always stored in the analysis dict regardless of active source.

## Session artifact schema

`data/sessions/{session_id}.json`:
```json
{
  "sessionId": "20260502T...-query-slug-paperid",
  "query": "user search string",
  "selectedPaper": { "paperId": "...", "title": "...", "year": 2024, ... },
  "graphPath": "data/graphs/{session_id}.json",
  "reportPath": "data/reports/{session_id}.md",
  "sourcesPath": "data/sources/{session_id}.json",
  "analysis": {
    "seedPaper": {...},
    "topPapers": [...],
    "clusters": [...],
    "priorWorks": [...],
    "derivativeWorks": [...],
    "cpPriorWorks": [...],
    "cpDerivativeWorks": [...],
    "bfsOrder": [...],
    "dfsOrder": [...],
    "trendSummary": [...],
    "openQuestions": [...]
  },
  "savedAt": "2026-05-02T..."
}
```

## Cache check logic

`run_research.py` scans `data/sessions/*.json` (newest first) looking for a session where `selectedPaper.paperId` matches the paper found by the Semantic Scholar search. If found, the graph is loaded from `session["graphPath"]` and no Connected Papers credit is consumed.

## Connected Papers credit cost

- Each unique paper graph fetch = **1 credit** (50/month default)
- Cache hits = **0 credits**
- `run_research.py` always performs the cache check first

## Error cases

| Error | Likely cause | Fix |
|---|---|---|
| `503 Service Unavailable` (Semantic Scholar or CP) | Clash proxy not running or overloaded | Start Clash, wait and retry |
| `No papers found` | Query too specific or unusual title | Try shorter title or different phrasing |
| `Connected Papers returned no graph data` | Paper ID not indexed by CP | Try a different seed paper |
| `Session not found` | Wrong session_id passed to answer_question.py | Check data/sessions/ for correct ID |
| `401 AuthenticationError` | OPENAI_API_KEY invalid or expired | Update key in .env |

## Retrieval for Q&A

`answer_question.py` uses `src/utils/retrieval.retrieve_context()` — a lexical (bag-of-words) ranker that scores document chunks by token overlap with the question. It searches across: report sections, cluster summaries, prior/derivative work titles, BFS/DFS orders, and individual paper abstracts. The top 6 chunks are injected into the LLM prompt alongside the full report markdown.
