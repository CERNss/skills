---
name: fact-based-dashboard
description: Create observability implementation docs and dashboard designs strictly from repository documents and code facts. Use when a user asks to design dashboards or write observability plans from a codebase/design docs (e.g., "画dashboard", "做观测面板", "按这个md格式输出") and explicitly requires no assumptions, no compatibility fallbacks, and traceable evidence.
---

# Fact Based Dashboard

Build dashboard and observability outputs from verifiable repository facts only.

## Workflow

1. Lock scope and deliverables.
- Confirm diagram type (`architecture`, `dataflow`, or `observability`).
- Confirm output paths.
- Confirm whether a structured observability md is required.
- Confirm whether both `Full` and `Lite(one-page)` dashboard variants are required.
- State that only evidence-backed statements/nodes/edges will be included.

2. Build a fact inventory before drawing.
- Read user-specified docs first.
- Extract concrete entities from code/docs: services, jobs, queues, events, APIs, metrics, storage.
- Record every fact with file path and line reference.
- If a relation cannot be proven, mark it as `unknown` instead of inferring.

3. Convert facts into output models.
- If the user requires the `backend-doc/tcg-wiki/otel/tcg-wiki-observability-analysis.md` format, generate the md by filling the template at:
  [references/tcg-observability-analysis-template.md](references/tcg-observability-analysis-template.md)
- If the user requires SigNoz dashboard JSON, build from:
  [assets/signoz-dashboard-otlp-v1-template.json](assets/signoz-dashboard-otlp-v1-template.json)
  and keep dashboard `description` aligned with the unified convention at:
  [references/dashboard-description-conventions.md](references/dashboard-description-conventions.md)
- Dashboard wording rule (default): treat all selected metrics as implemented in panel titles/tags/descriptions.
- Dashboard terminology rule (default): do not split by `baseline/planned`; use neutral `Overview` terminology unless user explicitly asks to keep those terms.
- Lite wording rule: first row must be a section header (not a metric), title it `一屏总览（值班核心健康信号）`.
- Node = concrete component found in sources.
- Edge = concrete interaction found in sources.
- Edge labels use exact terms from sources (event type, endpoint, method, metric, task kind).
- Keep naming identical to source terms.

4. Render outputs.
- Produce a standalone diagram file (`.html` with inline SVG preferred).
- Produce the structured observability md when requested.
- Produce SigNoz JSON output(s): `Full` only, or `Full + Lite` when requested.
- Produce a companion facts file mapping each node/edge to evidence.

5. Run quality gate before delivery.
- Verify template section order and headings when md is requested.
- Verify each node has evidence.
- Verify each edge has evidence.
- Remove speculative wording (`likely`, `probably`, `assume`, fallback logic).
- Ensure scope boundaries are explicit (what is included/excluded).
- Verify no unintended `baseline/planned` wording remains when user wants unified semantics.

## Output Contract

Deliverables depend on request:

1. Structured observability md (when requested)
- Must follow `references/tcg-observability-analysis-template.md` section order and heading hierarchy.
- Must keep section numbering (`1`..`6`, `1.1`, `1.2`, ...).
- Must mark unknown or pending facts explicitly as `待确认` instead of guessing.

2. Diagram file (when requested)
- Self-contained HTML/SVG.
- Clear title and scope.
- Distinguish sync vs async edges when source evidence supports it.

3. SigNoz dashboard JSON (when requested)
- Must use top-level structure compatible with existing `v4` dashboards (`name`, `description`, `layout`, `widgets`, `tags`, `variables`, `version`).
- Must keep panel query shape consistent with existing OTLP builder patterns.
- Must align `description` wording with the unified convention, then fill service-specific facts.
- Default terminology must use `Overview`; avoid `baseline/planned` split unless user explicitly requires it.
- If `Lite` is requested, it must be one-page and its first row title must be `一屏总览（值班核心健康信号）`.

4. Facts mapping file (`*-facts.md`)
- `Node/Edge -> Evidence` table.
- `Unknowns` section for unresolved but requested relationships.

## References

- Use [references/fact-extraction-patterns.md](references/fact-extraction-patterns.md) for repeatable extraction commands and fact-table format.
- Use [references/diagram-quality-gate.md](references/diagram-quality-gate.md) as the final pre-delivery checklist.
- Use [references/tcg-observability-analysis-template.md](references/tcg-observability-analysis-template.md) as the required md skeleton when the user asks for that format.
- Use [references/dashboard-description-conventions.md](references/dashboard-description-conventions.md) as the single unified `description` and terminology convention.

## Assets

- Use [assets/repo-fact-diagram-template.html](assets/repo-fact-diagram-template.html) as a starter template for standalone diagrams.
- Use [assets/signoz-dashboard-otlp-v1-template.json](assets/signoz-dashboard-otlp-v1-template.json) as a starter template for SigNoz dashboard JSON.
