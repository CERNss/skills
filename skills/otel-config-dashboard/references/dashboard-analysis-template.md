# <repo_name> Dashboard Analysis Template

Use this template to keep dashboard analysis documents aligned with fact-traceable full/lite generation.

## Required Section Order

1. `## 1. 范围与目标`
2. `## 2. 事实来源`
3. `## 3. 设计约束（硬约束）`
4. `## 4. 遥测模型与指标契约`
5. `## 5. 模板族与分区装配`
6. `## 6. full / lite 生成策略`
7. `## 7. 下钻能力与可见性边界`
8. `## 8. 事实追踪映射`
9. `## 9. 验收标准`
10. `## 10. 产物清单`

## Required Details

1. Section 2 must include:
   - dashboard output paths in `./<repo_name>/dashboard/`
   - code/doc/user evidence sources
   - existing canonical JSON or markdown docs if present
   - concrete evidence references in `path:line` format
2. Section 3 must define:
   - metric scope rule: no guessed metrics and no compatibility aliases unless explicitly requested
   - label boundary rule: low-cardinality only
   - service scope and out-of-scope boundaries
   - lite one-page rule
3. Section 4 must include:
   - telemetry model summary
   - exact metric list used by dashboards
   - allowed labels for filters/groupBy/variables
   - link or inline reference to metrics contract rows
4. Section 5 must explain:
   - selected packs and evidence basis
   - omitted packs and omission reason
5. Section 6 must compare:
   - full coverage goal
   - lite one-page oncall goal
   - widget selection differences and retention rationale
6. Section 7 must state:
   - trace readiness
   - log correlation readiness
   - service-map readiness
   - fallback behavior when drilldown is incomplete
7. Section 8 must include:
   - metric -> panel -> evidence mapping summary
   - label-boundary evidence summary
   - `待确认` items with reason and blocker
8. Section 9 must include:
   - importability check for full and lite JSON
   - metric-key contract check
   - layout/widgets mapping check
   - lite one-page check
   - traceability check against facts mapping file

## Naming Convention

1. Analysis filename: `./<repo_name>/dashboard/<repo_name>-dashboard-analysis.md`
2. Full dashboard filename: `./<repo_name>/dashboard/<repo_name>-dashboard-otlp-v1.json`
3. Lite dashboard filename: `./<repo_name>/dashboard/<repo_name>-dashboard-otlp-lite-v1.json`
4. Facts mapping filename: `./<repo_name>/dashboard/<repo_name>-dashboard-facts.md`
5. Title format: `# <repo_name> 服务看板设计（OTLP v2）`

## Content Rules

1. Keep structure stable; adapt facts and telemetry content only.
2. Mark unknowns as `待确认`.
3. The lite first row title must be `一屏总览（值班核心健康信号）`.
4. Explain why each lite panel is retained.
5. Explain how users move from lite to full or traces/logs when incidents happen.
6. Do not use speculative language (`likely`, `probably`, `assume`).
