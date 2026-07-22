# <repo_name> 可观测性实施清单

## 1. 可观测性目标模型

### 1.1 命名约定（单仓库）

- `APP_NAME=<repo_name>`
- `OTEL_SERVICE_NAME`:
  - `<service-name-1>`
  - `<service-name-2>`
  - `<service-name-3>`
  - `<service-name-4>`
- `OTEL_RESOURCE_ATTRIBUTES`:
  - `service.namespace=<namespace>,deployment.environment=<env>,service.version=<version>`

### 1.2 统一关联字段

1. 请求链路: `<field-a>`, `<field-b>`, `<field-c>`
2. 异步任务链路: `<field-a>`, `<field-b>`, `<field-c>`
3. 事件链路: `<field-a>`, `<field-b>`, `<field-c>`
4. 发布链路: `<field-a>`, `<field-b>`, `<field-c>`
5. 后台任务链路: `<field-a>`, `<field-b>`, `<field-c>`

### 1.3 指标最小集

1. `<metric_1>{<label_1>,<label_2>}`
2. `<metric_2>`
3. `<metric_3>`
4. `<metric_4>`
5. `<metric_5>`
6. `<metric_6>`
7. `<metric_7>`
8. `<metric_8>`
9. `<metric_9>`
10. `<metric_10>`
11. `<metric_11>`
12. `<metric_12>`

## 2. 基于 OBSERVABILITY_REPO 的实施清单

### 2.1 代码实施项

1. `<code-path-1>`
   - `<改造点>`
2. `<code-path-2>`
   - `<改造点>`
3. `<code-path-3>`
   - `<改造点>`
4. `<code-path-4>`
   - `<改造点>`
5. `<code-path-5>`
   - `<改造点>`

### 2.2 GitOps 注入项

1. `<gitops-path-1>`
   - `APP_NAME=<repo_name>`
   - `OTEL_SERVICE_NAME=<service-name>`
   - `OTEL_RESOURCE_ATTRIBUTES=service.namespace=<namespace>,deployment.environment=<env>,service.version=<version>`
2. `<gitops-path-2>`
   - `APP_NAME=<repo_name>`
   - `OTEL_SERVICE_NAME=<service-name>`
   - `OTEL_RESOURCE_ATTRIBUTES=...`
3. `<gitops-path-3>`
   - `APP_NAME=<repo_name>`
   - `OTEL_SERVICE_NAME=<service-name>`
   - `OTEL_RESOURCE_ATTRIBUTES=...`

## 3. 基线外补充建议（可并行纳入）

1. `<风险标题>`
`<风险描述>`

2. `<风险标题>`
`<风险描述>`

3. `<风险标题>`
`<风险描述>`

## 4. 实施优先级建议

### P0（先打通主链路）

1. `<P0-项1>`
2. `<P0-项2>`
3. `<P0-项3>`

### P1（提升排障效率）

1. `<P1-项1>`
2. `<P1-项2>`
3. `<P1-项3>`

### P2（观测产品化）

1. `<P2-项1>`
2. `<P2-项2>`
3. `<P2-项3>`

## 5. 执行规划

1. 分工建议（3-4 个 Agent 并行）：
   - Agent-A：`<文件范围>`。目标：`<目标>`
   - Agent-B：`<文件范围>`。目标：`<目标>`
   - Agent-C：`<文件范围>`。目标：`<目标>`
2. 主负责人验收清单：
   - `<验收项1>`
   - `<验收项2>`
   - `<验收项3>`
3. 协作约定：
   - `<约定1>`
   - `<约定2>`
   - `<约定3>`

## 6. 实际应用

1. 硬约束：
   - `<硬约束1>`
   - `<硬约束2>`
   - `<硬约束3>`
2. 执行步骤：
   - `<步骤1>`
   - `<步骤2>`
   - `<步骤3>`
3. Prompt 模板：

```text
你是 <repo_name> observability 子任务 Agent。
目标：在指定文件范围内完成可观测性实施任务，不做额外扩展。

必须遵守：
1) 仅使用低基数 label：<labels>
2) 禁止把高基数字段放入 metrics label
3) *_total 用 counter，*_duration_ms 用 histogram(ms)
4) 不改动未分配给你的文件

你的文件范围：
<填写文件列表>

你的目标：
<填写指标/日志/配置目标>

交付要求：
1) 列出改动文件与作用
2) 列出新增/修改的指标及 labels
3) 给出自检结果（编译/测试/关键路径验证）
4) 给出回滚方案（删哪些点位即可回退）
```
