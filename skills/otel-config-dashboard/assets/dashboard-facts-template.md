# <repo_name> Dashboard Facts Mapping

## 1. 范围与证据来源

1. 服务范围：`<service-1>`、`<service-2>`。
2. 代码范围：`<code-path-1>`、`<code-path-2>`。
3. 文档范围：`<doc-path-1>`、`<doc-path-2>`。
4. 不包含：`<out-of-scope>`。

## 2. 事实清单（已确认）

| fact_id | fact_type | fact | evidence | source_kind | status | notes |
| --- | --- | --- | --- | --- | --- | --- |
| F-001 | service | `<service_name>` | `<path:line>` | code | confirmed |  |
| F-010 | metric | `<metric_name>` | `<path:line>` | code | confirmed | `<counter/histogram/gauge>` |
| F-020 | label | `<label_name>` | `<path:line>` | code | confirmed | low-cardinality |
| F-030 | dependency | `<dependency_name>` | `<path:line>` | doc | confirmed |  |

## 3. 指标 -> 面板 -> 证据映射

| panel | metric_name | contract_row | fact_ids | evidence |
| --- | --- | --- | --- | --- |
| `<panel_1>` | `<metric_1>` | `<contract-row-id>` | `F-010` | `<path:line>` |
| `<panel_2>` | `<metric_2>` | `<contract-row-id>` | `F-011,F-012` | `<path:line>; <path:line>` |

## 4. 标签边界映射

| label | used_in | fact_ids | evidence | allowed |
| --- | --- | --- | --- | --- |
| `<label_1>` | `groupBy` | `F-020` | `<path:line>` | yes |
| `<label_2>` | `filter` | `F-021` | `<path:line>` | yes |

## 5. 依赖与链路映射

| flow_or_dependency | panels | fact_ids | evidence | notes |
| --- | --- | --- | --- | --- |
| `<http request flow>` | `<panel_1,panel_2>` | `F-040,F-041` | `<path:line>` |  |
| `<queue consumer flow>` | `<panel_3>` | `F-050` | `<path:line>` |  |

## 6. 待确认项

| item | reason | blocker | next action |
| --- | --- | --- | --- |
| `<unknown_item_1>` | evidence missing | `<missing-source>` | `<how to confirm>` |
| `<unknown_item_2>` | ambiguous naming | `<owner/path>` | `<how to confirm>` |
