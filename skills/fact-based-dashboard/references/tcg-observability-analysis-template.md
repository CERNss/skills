# <repo_name> 可观测性分析（事实驱动）

## 1. 范围与目标

### 1.1 范围

1. 服务范围：`<service-1>`、`<service-2>`。
2. 代码范围：`<code-path-1>`、`<code-path-2>`。
3. 不包含：`<out-of-scope>`。

### 1.2 目标

1. 明确可观测契约（指标/标签/链路）。
2. 形成可直接落地的看板与实施清单。

### 1.3 指标最小集

1. `<metric_1>{<label_a>,<label_b>}`
2. `<metric_2>`
3. `<metric_3>`

## 2. 基于仓库事实的实施清单

### 2.1 代码实施项

1. `<module/path>`：补充 `<metric_x>`。
2. `<module/path>`：统一标签 `<label_y>`。

### 2.2 配置实施项

1. OTel 资源属性：`service.name`、`deployment.environment`。
2. 导出链路：OTLP -> SigNoz。

## 3. 指标与标签契约

### 3.1 指标定义

| 指标名 | 类型 | 单位 | 允许标签 | 聚合建议 |
|---|---|---|---|---|
| `<metric_1>` | Counter | none | `<label_a>,<label_b>` | rate/increase |

### 3.2 标签边界

1. 允许：低基数标签（`status`、`method`、`topic` 等）。
2. 禁止：高基数标签（`trace_id`、`user_id`、`uuid` 等）。

## 4. Dashboard 设计映射

### 4.1 分区

1. `Overview`
2. `<section_2>`
3. `<section_3>`

### 4.2 指标到面板映射

| 面板 | 指标 | 查询方式 | 证据 |
|---|---|---|---|
| `<panel_1>` | `<metric_1>` | rate | `<path:line>` |

## 5. 质量门禁与差距

### 5.1 质量门禁

1. 指标键全部可追溯到事实源。
2. `layout` 与 `widgets` 一一映射。
3. 不含兼容回退或猜测性查询。

### 5.2 差距与待确认

1. `<gap_item_1>`：待确认。
2. `<gap_item_2>`：待确认。

## 6. 产物与落地计划

### 6.1 产物

1. `./<repo_name>/otel/<repo_name>-observability-analysis.md`
2. `./<repo_name>/dashboard/<repo_name>-service-dashboard-otlp-v1.json`
3. `./<repo_name>/dashboard/<repo_name>-service-dashboard-otlp-lite-v1.json`（可选）

### 6.2 落地顺序

1. 先落指标与标签。
2. 再导入 Full 面板。
3. 最后导入 Lite 一屏总览并联调告警。
