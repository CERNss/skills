# <repo_display_name> 服务看板设计（OTLP v2）

## 1. 范围与目标

1. 本文档定义 `<repo_name>` 的服务级 SigNoz 看板设计。
2. 目标是基于已确认事实建立最小可观测闭环，用于首轮上线与排障。
3. 本文档不覆盖域级跨服务大盘。

## 2. 事实来源

1. 可观测设计文档：
   - `./<repo_name>/otel/<repo_name>-observability-analysis.md`
2. 面板产物：
   - `<resolved-full-dashboard-json-path>`
   - `<resolved-lite-dashboard-json-path>`
3. 代码链路范围：
   - `<code-scope-1>`
   - `<code-scope-2>`
   - `<code-scope-3>`

## 3. 设计约束（硬约束）

1. 仅使用可观测文档定义的已确认指标，不引入猜测指标。
2. 仅使用文档允许的低基数标签，不引入额外业务标签。
3. 服务范围固定为已确认服务集合。
4. 不做兼容查询、别名查询、回退查询。

## 4. 指标与标签契约

### 4.1 指标清单（N项）

1. `<metric_1>`
2. `<metric_2>`
3. `<metric_3>`
4. `<metric_4>`
5. `<metric_5>`

### 4.2 标签边界

1. 允许标签：`<label_1>`、`<label_2>`、`<label_3>`。
2. 禁止使用契约外标签作为分组维度。

## 5. 看板版本与使用场景

1. `完整版（Full）`：`<full-json-filename>`
   - 用于深度排障与分链路分析。
2. `精简版（Lite）`：`<lite-json-filename>`
   - 用于值班一屏巡检与快速健康判断。
   - 首行为 `一屏总览（值班核心健康信号）` 分区标题，不是单独指标。

## 6. 面板分区（与 JSON 对应）

1. `Overview`
2. `<section-2>`
3. `<section-3>`
4. `<section-4>`

## 7. 查询与展示策略

1. `*_total` 以 `increase` 或 `rate` 展示吞吐与结果分布。
2. `*_duration_ms` 以 `avg`、`p50`、`p90`、`p99` 展示时延。
3. 分组维度仅来自本文件第 4 节定义的契约标签。
4. 不使用兼容查询、别名查询、回退查询。

## 8. 验收标准

1. JSON 可被 SigNoz 正常导入。
2. 每个 widget 的指标名均在本文件指标清单内。
3. 每个分组标签均在允许标签集合内。
4. `layout` 与 `widgets` 一一映射。

## 9. 产物清单

1. 完整版 JSON：`<full-json-filename>`
2. 精简版 JSON：`<lite-json-filename>`
3. 设计文档：`<repo_name>-dashboard.md`
