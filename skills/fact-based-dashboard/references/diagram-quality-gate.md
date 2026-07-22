# Diagram Quality Gate

Use this checklist before delivering any fact-based diagram/dashboard analysis output.

## 1. Evidence Integrity

1. Every node has at least one evidence reference (`path:line`).
2. Every edge has at least one evidence reference (`path:line`).
3. If evidence is missing, the item is marked `待确认` or removed.

## 2. Scope Control

1. Included components are inside user-requested scope.
2. Out-of-scope components are explicitly excluded.
3. No inferred cross-service relation without evidence.

## 3. Terminology Consistency

1. Names match repository source terms exactly.
2. Dashboard section naming defaults to `Overview`.
3. Avoid `baseline/planned` split wording unless user explicitly requests it.

## 4. Query/Metric Consistency

1. Every metric key used in dashboard JSON appears in contract/docs/code facts.
2. `groupBy` labels are low-cardinality and contract-approved.
3. No fallback alias query and no speculative metric name.

## 5. Lite One-Page Rule (when applicable)

1. Lite dashboard first row title is `一屏总览（值班核心健康信号）`.
2. First row is a section header, not an independent metric claim.
3. Layout and widgets map one-to-one.

## 6. Final Delivery Gate

1. JSON syntax valid (for dashboard outputs).
2. Required sections and heading order match template.
3. Unknowns are explicit and actionable.
