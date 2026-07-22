# <repo_name> 服务看板设计（OTLP v2）

## 1. 范围与目标

1. 本文档定义 `<repo_name>` 的通用化 SigNoz 服务看板设计。
2. 默认产物包含两份 JSON：完整版 `full` 与一屏值班版 `lite`。
3. 本方案坚持事实驱动，所有关键结论均可追踪到证据源。

## 2. 事实来源

1. 用户提供输入：
   - `<architecture-note>`
   - `<metric-or-instrumentation-inventory>`
   - `<span-naming-note>`
2. 代码 / 文档证据（`path:line`）：
   - `<code-scope-1:line>`
   - `<code-scope-2:line>`
   - `<code-scope-3:line>`
3. 既有产物锚点（如有）：
   - `<canonical-dashboard-or-doc-path:line>`
4. 输出路径：
   - `./<repo_name>/dashboard/<repo_name>-dashboard-otlp-v1.json`
   - `./<repo_name>/dashboard/<repo_name>-dashboard-otlp-lite-v1.json`
   - `./<repo_name>/dashboard/<repo_name>-dashboard-analysis.md`
   - `./<repo_name>/dashboard/<repo_name>-dashboard-facts.md`

## 3. 设计约束（硬约束）

1. 仅使用已确认事实中的指标与标签，不新增、不猜测、不做兼容别名。
2. 仅使用允许的低基数标签，不引入高基数业务标签。
3. lite 必须保持单页，并只保留核心值班信号。
4. trace / log / service map 能力缺失时，必须显式写明可见性边界。
5. 未能证明的关系必须标记为 `待确认`，不得作为已实现能力呈现。

## 4. 遥测模型与指标契约

### 4.1 服务范围

1. `<service-name-1>`
2. `<service-name-2>`
3. `<service-name-3>`

### 4.2 指标契约摘要

1. `<metric_1>`
2. `<metric_2>`
3. `<metric_3>`
4. `<metric_4>`
5. `<metric_5>`

### 4.3 标签边界

1. 允许标签：`<label_1>`、`<label_2>`、`<label_3>`。
2. 禁止高基数字段作为分组维度，如 ID、UUID、`trace_id`、`user_id`。

## 5. 模板族与分区装配

1. 基础健康包：`<base-pack>`（证据：`<path:line>`）
2. 错误与归因包：`<error-pack>`（证据：`<path:line>`）
3. 依赖包：`<dependency-pack>`（证据：`<path:line>`）
4. 下钻包：`<drilldown-pack>`（证据：`<path:line>`）
5. 未纳入包与原因：`<omitted-pack-reason>`

## 6. full / lite 生成策略

### 6.1 full

1. 目标：完整覆盖 + 深度排障。
2. 分区：
   - `Service Health`
   - `Errors / Exceptions`
   - `<section-3>`
   - `<section-4>`
   - `Trace / Log Drilldown`

### 6.2 lite

1. 目标：单页值班 + 快速下钻。
2. 首行标题：`一屏总览（值班核心健康信号）`
3. 保留理由：
   - `<lite-widget-1>: <保留原因>`
   - `<lite-widget-2>: <保留原因>`
   - `<lite-widget-3>: <保留原因>`

## 7. 下钻能力与可见性边界

1. traces：`<ready-or-not>`
2. logs correlation：`<ready-or-not>`
3. service map：`<ready-or-not>`
4. fallback：`<fallback-behavior-if-needed>`

## 8. 事实追踪映射

1. 指标到面板映射摘要（详见 facts 文件）：
   - `<panel-name>` <- `<metric_name>` <- `<fact_id>` <- `<path:line>`
2. 标签边界映射摘要：
   - `<label>` <- `<fact_id>` <- `<path:line>`
3. 待确认项摘要：
   - `<item>`：`待确认`（阻塞原因：`<reason>`）

## 9. 验收标准

1. 两份 JSON 都可被 SigNoz 正常导入。
2. 每个 widget 的指标名均在指标契约内。
3. 每个分组标签均在允许标签集合内。
4. lite 为单页，且只保留高信号内容。
5. `layout` 与 `widgets` 一一映射。
6. facts 映射文件完整覆盖关键面板与关键指标。

## 10. 产物清单

1. 完整版看板 JSON：`./<repo_name>/dashboard/<repo_name>-dashboard-otlp-v1.json`
2. 精简版看板 JSON：`./<repo_name>/dashboard/<repo_name>-dashboard-otlp-lite-v1.json`
3. 解析文档：`./<repo_name>/dashboard/<repo_name>-dashboard-analysis.md`
4. 事实映射：`./<repo_name>/dashboard/<repo_name>-dashboard-facts.md`
