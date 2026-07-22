# <repo_name> 可观测性实施清单模板

Use this template to keep the same architecture as existing canonical observability deliverables.

## Required Section Order

1. `## 1. 可观测性目标模型`
2. `## 2. 基于 OBSERVABILITY_REPO 的实施清单`
3. `## 3. 基线外补充建议（可并行纳入）`
4. `## 4. 实施优先级建议`
5. `## 5. 执行规划`
6. `## 6. 实际应用`

## Required Subsections

- Under section 1:
  - `### 1.1 命名约定（单仓库）`
  - `### 1.2 统一关联字段`
  - `### 1.3 指标最小集`
- Under section 2:
  - `### 2.1 代码实施项`
  - `### 2.2 GitOps 注入项`
- Under section 4:
  - `### P0（先打通主链路）`
  - `### P1（提升排障效率）`
  - `### P2（观测产品化）`

## Style Constraints

1. Use Chinese headings and numbered sections exactly as above.
2. Keep each actionable item mapped to concrete file paths or deployment paths.
3. Keep metric and label rules explicit, including high-cardinality exclusions.
4. Include an execution prompt template in section 6 for delegated implementation.
5. If facts are missing, mark as `待确认` instead of inferring.

## Minimal Data Blocks

1. Service naming block:
   - `APP_NAME=<repo_name>`
   - `OTEL_SERVICE_NAME=<service-a>, <service-b>, ...`
   - `OTEL_RESOURCE_ATTRIBUTES=service.namespace=...,deployment.environment=...,service.version=...`
2. Correlation fields block:
   - request chain fields
   - async chain fields
   - event chain fields
3. Metrics minimum set block:
   - numbered list with explicit metric names and labels
