# Dashboard Description Unified Convention

This document defines one unified `description` and terminology convention for SigNoz dashboards in this skill.

Source alignment set:

1. `backend-doc/tcg-wiki/dashboard/tcg-wiki-service-dashboard-otlp-v1.json`
2. `backend-doc/tcg-wiki/dashboard/tcg-wiki-service-dashboard-otlp-lite-v1.json`
3. `backend-doc/tcg-binder/dashboard/tcg-binder-service-dashboard-otlp-v1.json`
4. `backend-doc/tcg-binder/dashboard/tcg-binder-service-dashboard-otlp-lite-v1.json`
5. `backend-doc/tcg-binder/dashboard/tcg-binder-dashboard.md`

## Unified rule

Use exactly one sentence, and organize it as:

`<app> SigNoz 面板。基于<事实来源>定义的<指标范围/链路范围>设计，服务范围为<service list>，覆盖<关键链路列表>，不做兼容查询与假设扩展。`

Notes:

1. If a field has no evidence in source facts, omit that phrase instead of inventing content.
2. Keep nouns and service names identical to repository sources.
3. Never add fallback/alias language.
4. By default, express included metrics as implemented in panel wording.

## Terminology guardrails

1. Use `Overview` as the first section naming in dashboard structure.
2. Avoid `baseline/planned` split wording in dashboard tags, row titles, and panel titles unless the user explicitly requests those terms.
3. For `Lite` one-page dashboards, the first row title should be `一屏总览（值班核心健康信号）` to make it obvious this is a section header.
4. Keep metric naming fact-based; do not invent extra metrics or fallback aliases.

## Minimum required fields

1. Subject: `<app> SigNoz 面板`
2. Fact source scope: document or code-fact scope used for this dashboard
3. Service scope: explicit `service.name` list when available
4. Coverage scope: explicit business chain/metric scope supported by facts
5. Constraint: include `不做兼容查询与假设扩展`

## Example from tcg-wiki facts

`tcg-wiki SigNoz 面板。基于可观测性文档定义的 12 项最小指标与标签约束设计，服务范围为 tcg-wiki-http / tcg-wiki-rpc / tcg-wiki-match-rule / tcg-wiki-syncer，覆盖 SyncTask、Match-Rule/IDLinker、Cache/Dynamo 链路，不做兼容查询与假设扩展。`

## Example from tcg-binder facts

`tcg-binder SigNoz 面板。基于服务可观测性与看板文档定义的指标能力设计，服务范围为 tcg-binder-http / tcg-binder-worker，覆盖 Inventory、Valuation、Worker、MQ、Wiki RPC、Cache、Persistence 链路，不做兼容查询与假设扩展。`

## Hard checks

1. Single sentence only.
2. Single unified rule only: no A/B variants and no branching rules.
3. No claims beyond evidence-backed scope.
4. If Lite is delivered, first row title must be `一屏总览（值班核心健康信号）`.
