# Fact Traceability Quality Gate

Run this gate before delivering dashboard outputs.

## 1. Evidence Integrity

1. Every selected metric has at least one evidence reference (`path:line`).
2. Every selected label has at least one evidence reference (`path:line`).
3. Every selected dependency/flow claim has evidence.
4. If evidence is missing, mark item `待确认` or remove it from generated outputs.

## 2. Scope Control

1. Included services/components are within user-requested scope.
2. Out-of-scope components are explicitly listed.
3. No inferred cross-service relation without evidence.

## 3. Contract Consistency

1. Every dashboard metric key exists in metrics contract.
2. Every `must_visualize=true` metric appears in at least one panel.
3. `groupBy`/filter/variable labels are all contract-approved low-cardinality labels.
4. No alias/fallback metric names are used unless explicitly requested.

## 4. Full/Lite Profile Integrity

1. Full preserves coverage and triage intent.
2. Lite remains one page and first row title is `一屏总览（值班核心健康信号）`.
3. Lite keeps only high-signal content.
4. Drilldown entries match actual readiness (trace/log/service map).

## 5. Legacy Markdown Contract Integrity

1. Observability markdown exists at `./<repo_name>/otel/<repo_name>-observability-analysis.md`.
2. Dashboard markdown exists at `./<repo_name>/dashboard/<repo_name>-dashboard.md`.
3. Observability markdown follows the required section order and subsection hierarchy.
4. Dashboard markdown follows the required section order and subsection hierarchy.
5. Heading numbering and wording remain stable unless redesign was explicitly requested.

## 6. Delivery Integrity

1. Full and lite JSON are importable.
2. `layout` and `widgets` map one-to-one.
3. Output JSON filenames are canonical or explicitly approved alternatives.
4. If facts mapping is requested, it exists and is complete.
5. Unknowns are explicit, actionable, and separated from confirmed facts.
6. Speculative wording is removed (`likely`, `probably`, `assume`).
