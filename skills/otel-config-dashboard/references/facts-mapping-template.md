# Facts Mapping Template

Use this template for `./<repo_name>/dashboard/<repo_name>-dashboard-facts.md`.

## Required Sections

1. `## 1. 范围与证据来源`
2. `## 2. 事实清单（已确认）`
3. `## 3. 指标 -> 面板 -> 证据映射`
4. `## 4. 标签边界映射`
5. `## 5. 依赖与链路映射`
6. `## 6. 待确认项`

## Required Fields

- Fact rows must include:
  - `fact_id`
  - `fact_type`
  - `fact`
  - `evidence (path:line)`
  - `source_kind`
  - `status`
- Mapping rows must include:
  - dashboard panel name
  - metric key
  - contract row reference
  - one or more `fact_id`
  - one or more `path:line`

## Hard Rules

1. Every confirmed panel metric must map to at least one confirmed fact row.
2. Every label in filters/groupBy/variables must have evidence.
3. `待确认` items must not be mixed into confirmed mapping rows.
4. If canonical dashboard panels are retained, include retained panel evidence anchors.
