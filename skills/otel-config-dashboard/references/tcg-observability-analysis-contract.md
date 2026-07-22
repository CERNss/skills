# Legacy Observability Markdown Contract

Use this contract when generating `./<repo_name>/otel/<repo_name>-observability-analysis.md`.

## Filename And Title

1. Filename must be exactly `<repo_name>-observability-analysis.md` under `otel/`.
2. Title must be exactly `# <repo_name> 可观测性实施清单`.

## Required Section Order

1. `## 1. 可观测性目标模型`
2. `## 2. 基于 OBSERVABILITY_REPO 的实施清单`
3. `## 3. 基线外补充建议（可并行纳入）`
4. `## 4. 实施优先级建议`
5. `## 5. 执行规划`
6. `## 6. 实际应用`

## Required Subsections

1. Under section 1:
   - `### 1.1 命名约定（单仓库）`
   - `### 1.2 统一关联字段`
   - `### 1.3 指标最小集`
2. Under section 2:
   - `### 2.1 代码实施项`
   - `### 2.2 GitOps 注入项`
3. Under section 4:
   - `### P0（先打通主链路）`
   - `### P1（提升排障效率）`
   - `### P2（观测产品化）`

## Stability Rules

1. Preserve section numbering and heading wording unless user requests redesign.
2. Keep item style compatible with canonical `backend-doc/tcg-wiki/otel` documents.
3. Map actionable items to concrete code or deployment paths.
4. Mark missing facts as `待确认` instead of inference.
