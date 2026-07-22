# Legacy Dashboard Markdown Contract

Use this contract when generating `./<repo_name>/dashboard/<repo_name>-dashboard.md`.

## Filename And Title

1. Filename must be exactly `<repo_name>-dashboard.md` under `dashboard/`.
2. Title format: `# <Display Name> 服务看板设计（OTLP v2）`.

## Required Section Order

1. `## 1. 范围与目标`
2. `## 2. 事实来源`
3. `## 3. 设计约束（硬约束）`
4. `## 4. 指标与标签契约`
5. `## 5. 看板版本与使用场景`
6. `## 6. 面板分区（与 JSON 对应）`
7. `## 7. 查询与展示策略`
8. `## 8. 验收标准`
9. `## 9. 产物清单`

## Required Subsections

1. Under section 4:
   - `### 4.1 指标清单（N项）`
   - `### 4.2 标签边界`

## Style Rules

1. Keep Chinese headings and numbered sections stable.
2. Section 2 must include observability markdown path and both full/lite dashboard JSON paths.
3. Section 3 must keep hard constraints explicit: metric scope, label scope, service scope.
4. Section 5 must keep full/lite intent clear and keep lite first row title constraint.
5. Section 9 must list full JSON, lite JSON, and dashboard markdown outputs.
6. Preserve wording style compatible with canonical `backend-doc/tcg-wiki/dashboard` documents.
