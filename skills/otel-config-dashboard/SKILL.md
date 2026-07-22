---
name: otel-config-dashboard
description: generate generic signoz observability deliverables from repository telemetry facts. use when users want reusable signoz dashboards from repository code information, metric or instrumentation inventories, opentelemetry span or metric naming, architecture notes, or existing signoz json. outputs both a full dashboard json for deep triage and a lite one-page dashboard json for oncall, while preserving legacy tcg observability and dashboard markdown contracts.
---

# OTel Config Dashboard

Build a shared telemetry model first, then generate reusable SigNoz deliverables from repository facts only.

This skill is a strict superset of fact-based extraction behavior:
- no assumptions for metrics, labels, dependencies, or flows
- no compatibility alias metrics unless the user explicitly asks for them
- every important claim must trace to `path:line` evidence
- unknown or unverifiable relationships must be marked as `待确认`
- when canonical deliverables already exist, file naming and section contracts must stay stable unless redesign is explicitly requested

## Scope Note

By default this skill focuses on telemetry contract + dashboard outputs.
The following are non-goals unless user explicitly asks:
- standalone diagram deliverables
- node/edge semantic-first outputs

## Deliverable Modes

Generate two related dashboard outputs from the same facts:
1. `full`: complete dashboard for health, status, dependency analysis, errors, and deep triage.
2. `lite`: one-page dashboard for oncall inspection, with only highest-signal widgets and fast drilldown entry points.

Default required markdown contracts:
- `./<repo_name>/otel/<repo_name>-observability-analysis.md`
- `./<repo_name>/dashboard/<repo_name>-dashboard.md`

Optional add-on outputs when requested:
- `./<repo_name>/dashboard/<repo_name>-dashboard-facts.md`
- `./<repo_name>/otel/observability-implementation-checklist.md`
- `./<repo_name>/otel/otel-collector-config.yaml`

## Input Modes

Choose the lightest mode that matches the evidence already available.

### Mode A: direct-input mode
Use this when the user already provides most facts:
- repository or service description
- architecture overview
- metric or instrumentation inventory
- OpenTelemetry span and metric naming
- existing dashboard JSON or docs

In this mode, do not force extra discovery work.

### Mode B: discovery-assisted mode
Use this when the user gives a repo, partial docs, or incomplete telemetry notes.
Build facts from:
- code paths and instrumentation usage
- existing dashboard JSON or markdown docs
- OTel config snippets
- explicit gaps or missing instrumentation evidence

If outputs from other local skills already contain telemetry extraction or gap analysis, treat those outputs as preferred stage-0 evidence.

## Workflow

### 0. Detect canonical artifacts and compatibility anchors
Before generation, check whether canonical artifacts already exist in the provided repo, docs, or uploaded files:
- existing full dashboard JSON
- existing lite dashboard JSON
- existing legacy dashboard markdown (`<repo_name>-dashboard.md`)
- existing legacy observability markdown (`<repo_name>-observability-analysis.md`)
- existing facts mapping markdown (`<repo_name>-dashboard-facts.md`)
- existing observability checklist markdown
- existing OTel collector config

If they exist and the user asks for update (not redesign):
- keep metric names stable unless contract redesign is requested
- keep file names stable
- keep section hierarchy and numbering stable
- preserve importable panel syntax and working query patterns
- refresh facts, evidence links, filters, variables, and drilldown coverage as needed
- if canonical content conflicts with confirmed repository facts (especially service.name, OTEL_SERVICE_NAME, WithServiceName(...), and runtime identity fields), prefer repository facts and update stale canonical wording; do not preserve stale names for compatibility unless the user explicitly asks.

### 1. Lock scope and output paths
Determine `repo_name` from repository directory or user-provided service name.

Default output root:

```text
./<repo_name>/
```

Always create:

```text
./<repo_name>/dashboard/
./<repo_name>/otel/
```

Resolve output filenames at scope lock:
1. If canonical names already exist, use exact canonical names.
2. Otherwise use defaults:
   - full JSON: `./<repo_name>/dashboard/<repo_name>-service-dashboard-otlp-v1.json`
   - lite JSON: `./<repo_name>/dashboard/<repo_name>-service-dashboard-otlp-lite-v1.json`
   - dashboard markdown: `./<repo_name>/dashboard/<repo_name>-dashboard.md`
   - observability markdown: `./<repo_name>/otel/<repo_name>-observability-analysis.md`

At scope-lock stage, explicitly confirm or state:
- included services and code/document scope
- excluded scope
- required deliverables (`full`, `lite`, dashboard md, observability md)
- optional deliverables (facts mapping md, OTel checklist, collector config)
- evidence-only rule: only evidence-backed statements are allowed

### 2. Build fact inventory before telemetry modeling
Build a fact inventory before writing telemetry contracts or dashboard JSON.

Use [references/fact-extraction-patterns.md](references/fact-extraction-patterns.md).

Required fact categories:
- services and environments
- request and async flows
- dependencies (db/cache/queue/external/scheduler/batch/worker)
- metrics and metric types
- labels and allowed dimensions
- trace readiness and span dimensions
- log correlation readiness
- existing dashboard/query compatibility anchors (if updating)

Record facts in a structured table with evidence fields:
- `fact_id`
- `fact_type`
- `fact`
- `evidence` (`path:line`)
- `source_kind` (`code`, `doc`, `json`, `config`, `user-input`)
- `status` (`confirmed` or `待确认`)

Rules:
- every dependency and flow claim must have at least one evidence row
- every metric used in dashboard queries must have evidence
- every label used in filters/groupBy/variables must have evidence
- if a relation cannot be proven, mark `待确认` and keep it out of confirmed packs

### 3. Build the shared telemetry model from confirmed facts
Build one telemetry model from confirmed facts only.

Telemetry model must include:
- service list
- deployment environments if known
- critical request flows and async flows
- dependency classes
- trace readiness (span availability and usable fields)
- log correlation readiness (`trace_id`/`span_id` link availability)
- metrics contract linkage (see step 4)

Model rules:
- keep metric names exact
- do not invent fallback aliases
- model entries should reference corresponding fact rows where possible

### 4. Build metrics contract with evidence linkage
Build and validate metrics contract using [references/metrics-contract.md](references/metrics-contract.md).

Hard rules:
- each contract metric row must include fact linkage and `path:line` evidence
- each dashboard metric key must exist in contract
- each contract label boundary must be evidence-backed
- reject high-cardinality labels in `filters`, `groupBy`, and variables:
  - `trace_id`
  - `span_id`
  - `user_id`
  - `uuid`
  - raw entity IDs

### 5. Select dashboard packs (evidence-driven)
Use [references/template-taxonomy.md](references/template-taxonomy.md) to map telemetry model to packs.

Required packs:
- base health pack
- error and triage pack
- drilldown pack

Optional packs based on confirmed facts:
- api pack
- worker or async pack
- queue pack
- cache pack
- database pack
- external dependency pack
- scheduler or batch pack
- host or k8s pack
- frontend pack
- llm pack

Pack selection rules:
- do not add a pack without fact evidence
- if evidence is insufficient, mark as `待确认` in output docs

### 6. Generate full dashboard JSON
Start from [assets/signoz-dashboard-full-template.json](assets/signoz-dashboard-full-template.json).

Apply:
- [references/dashboard-profiles.md](references/dashboard-profiles.md)
- [references/drilldown-rules.md](references/drilldown-rules.md)
- [references/dashboard-description-conventions.md](references/dashboard-description-conventions.md)

Full dashboard rules:
- prioritize completeness and triage coverage
- include service health, error rate, throughput, latency views
- include dependency health for each confirmed dependency class
- include low-cardinality split views only
- include trace/log drilldown entry points when readiness exists
- if traces/logs are missing, keep drilldown limited and state limitation explicitly

Recommended rows (omit only when no evidence exists):
- `Service Health`
- `Errors / Exceptions`
- `API / Request Flows`
- `Workers / Async / Queue`
- `Dependencies`
- `Persistence / Cache / Database`
- `Trace / Log Drilldown`

Save to resolved full JSON path from step 1.

### 7. Generate lite dashboard JSON
Start from [assets/signoz-dashboard-lite-template.json](assets/signoz-dashboard-lite-template.json).

Apply:
- [references/dashboard-profiles.md](references/dashboard-profiles.md)
- [references/drilldown-rules.md](references/drilldown-rules.md)
- [references/dashboard-description-conventions.md](references/dashboard-description-conventions.md)

Lite rules:
- one page only
- first row title must be `一屏总览（值班核心健康信号）`
- keep roughly 8 to 12 widgets unless user requests otherwise
- every widget must support detection or fast triage
- preserve at least one high-value drilldown path when supported
- if trace/log correlation is unavailable, include best metric-only fallback and explain limitation

Save to resolved lite JSON path from step 1.

### 8. Generate legacy observability markdown (required)
Always generate legacy observability markdown.

Start from [assets/tcg-observability-analysis-template.md](assets/tcg-observability-analysis-template.md).
Follow:
- [references/tcg-observability-analysis-contract.md](references/tcg-observability-analysis-contract.md)
- [references/observability-implementation-template.md](references/observability-implementation-template.md)

Rules:
- title format must be `# <repo_name> 可观测性实施清单`
- keep section order and numbering as canonical style (`1` to `6`)
- keep required subsections (`1.1/1.2/1.3`, `2.1/2.2`, `P0/P1/P2`)
- map each actionable item to concrete file paths or deployment paths
- mark unknown or unverifiable items as `待确认`

Save to resolved observability markdown path from step 1.

### 9. Generate legacy dashboard markdown (required)
Always generate legacy dashboard markdown.

Start from [assets/dashboard-contract-template.md](assets/dashboard-contract-template.md).
Follow [references/dashboard-doc-template.md](references/dashboard-doc-template.md).

Rules:
- title format must be `# <Display Name> 服务看板设计（OTLP v2）`
- keep section order and numbering as canonical style (`1` to `9`)
- include observability markdown and JSON output paths in section 2/9
- keep hard constraints and metric/label boundaries explicit
- if canonical dashboard md exists, preserve naming style and section wording unless redesign is explicitly requested

Save to resolved dashboard markdown path from step 1.

### 10. Optionally generate companion facts mapping markdown
Generate when user asks for evidence appendix or strict traceability attachment.

Start from [assets/dashboard-facts-template.md](assets/dashboard-facts-template.md).
Follow [references/facts-mapping-template.md](references/facts-mapping-template.md).

Must include:
- evidence-backed fact inventory table
- metric -> panel -> evidence mapping
- label boundary evidence table
- dependency/flow evidence table
- unknowns (`待确认`) section separated from confirmed facts

Save to:
- `./<repo_name>/dashboard/<repo_name>-dashboard-facts.md`

### 11. Optionally generate linked OTel artifacts
Only when requested, generate:
- `./<repo_name>/otel/observability-implementation-checklist.md`
- `./<repo_name>/otel/otel-collector-config.yaml`

Use:
- [assets/otel-collector-config-template.yaml](assets/otel-collector-config-template.yaml)
- [assets/observability-implementation-checklist-template.md](assets/observability-implementation-checklist-template.md)
- [references/otel-config-checklist.md](references/otel-config-checklist.md)

These outputs must derive from the same telemetry model and evidence set.

### 12. Run traceability quality gate before delivery
Validate outputs before final delivery.

Run both checklists:
- [references/fact-traceability-quality-gate.md](references/fact-traceability-quality-gate.md)
- [references/otel-config-checklist.md](references/otel-config-checklist.md) (if collector config generated)

Required checks:
1. every dashboard metric key appears in metrics contract
2. every `must_visualize=true` metric appears in at least one panel (`full` preferred)
3. every `groupBy`, filter, and variable label belongs to allowed label set
4. every selected pack has fact evidence; unsupported packs are omitted or marked `待确认`
5. `layout` and `widgets` map one-to-one
6. full and lite outputs are importable SigNoz JSON
7. lite remains one page and keeps high-signal-only content
8. drilldown panels match actual trace/log/service-map readiness
9. legacy observability markdown follows required section order and numbering
10. legacy dashboard markdown follows required section order and numbering
11. scope boundaries and exclusions are explicit
12. speculative wording is removed (`likely`, `probably`, `assume`, fallback guessing)
13. if canonical artifacts exist, preserve compatible topology, naming, and section wording unless redesign was requested

Report mismatches first, then fix before final delivery.

## Output Contract

Default output tree:

```text
<repo_name>/
  dashboard/
    <repo_name>-service-dashboard-otlp-v1.json        # or canonical full JSON name
    <repo_name>-service-dashboard-otlp-lite-v1.json   # or canonical lite JSON name
    <repo_name>-dashboard.md
    <repo_name>-dashboard-facts.md                    # optional
  otel/
    <repo_name>-observability-analysis.md
    observability-implementation-checklist.md         # optional
    otel-collector-config.yaml                        # optional
```

Default required outputs:
- full dashboard JSON
- lite dashboard JSON
- legacy dashboard markdown (`<repo_name>-dashboard.md`)
- legacy observability markdown (`<repo_name>-observability-analysis.md`)

Optional add-ons:
- dashboard facts mapping markdown
- OTel implementation checklist
- OTel collector config

## Full vs Lite Intent

Use these exact mental models:
- `full = complete coverage + deep triage`
- `lite = one-page oncall + fast drilldown`

Do not let lite become a shrunk copy of full.
Do not let full become a noisy dump of every metric.

## Consistency Goal

For a new repository:
1. Keep output architecture stable.
2. Replace only service facts, metric facts, dependency facts, and evidence paths.
3. Mark unverifiable items as `待确认`.
4. Use official SigNoz template families as inspiration, but generate from repository telemetry facts.

For a repository with canonical dashboards/docs:
1. Prefer compatibility with existing metric and panel contract.
2. Preserve compatible query structure when possible.
3. Preserve canonical markdown contract (`otel/<repo>-observability-analysis.md` and `dashboard/<repo>-dashboard.md`) unless redesign was requested.

## References

- extraction commands and fact table rules: [references/fact-extraction-patterns.md](references/fact-extraction-patterns.md)
- metrics contract schema and evidence linkage: [references/metrics-contract.md](references/metrics-contract.md)
- pack selection rules: [references/template-taxonomy.md](references/template-taxonomy.md)
- full vs lite rules: [references/dashboard-profiles.md](references/dashboard-profiles.md)
- drilldown and readiness rules: [references/drilldown-rules.md](references/drilldown-rules.md)
- dashboard description convention: [references/dashboard-description-conventions.md](references/dashboard-description-conventions.md)
- dashboard markdown contract: [references/dashboard-doc-template.md](references/dashboard-doc-template.md)
- observability markdown contract: [references/tcg-observability-analysis-contract.md](references/tcg-observability-analysis-contract.md)
- facts mapping structure: [references/facts-mapping-template.md](references/facts-mapping-template.md)
- traceability quality gate: [references/fact-traceability-quality-gate.md](references/fact-traceability-quality-gate.md)
- OTel config checklist: [references/otel-config-checklist.md](references/otel-config-checklist.md)
- OTel checklist structure: [references/observability-implementation-template.md](references/observability-implementation-template.md)

## Assets

- full dashboard starter: [assets/signoz-dashboard-full-template.json](assets/signoz-dashboard-full-template.json)
- lite dashboard starter: [assets/signoz-dashboard-lite-template.json](assets/signoz-dashboard-lite-template.json)
- panel syntax starter: [assets/signoz-dashboard-template.json](assets/signoz-dashboard-template.json)
- dashboard markdown starter: [assets/dashboard-contract-template.md](assets/dashboard-contract-template.md)
- observability markdown starter: [assets/tcg-observability-analysis-template.md](assets/tcg-observability-analysis-template.md)
- facts mapping starter: [assets/dashboard-facts-template.md](assets/dashboard-facts-template.md)
- OTel checklist template: [assets/observability-implementation-checklist-template.md](assets/observability-implementation-checklist-template.md)
- OTel collector starter: [assets/otel-collector-config-template.yaml](assets/otel-collector-config-template.yaml)
