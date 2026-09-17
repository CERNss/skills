---
name: governing-otel-logs
description: >-
  裁定集换社服务能向 OpenTelemetry 与 SigNoz 出站哪些日志：哪些 ERROR、WARN 和业务事件必须导出，哪些健康探针访问日志、未采样 2xx、cron tick、循环内逐条日志、每条 SQL 和 payload dump 禁止导出，以及 Izumo access_log 采样与 severity 门槛怎样落地这条边界；用户要给服务接入或收敛 OTel 日志、排查 SigNoz 日志量与成本、或给新服务定日志基线时使用。
---

# 治理 OTel 日志

进入 OTel 的每一条日志，要么能触发行动，要么能回答一个业务问题。两者都不满足就不出站。

2026-09-02 的现网快照：24 小时进入 SigNoz 的日志 8562 万条，其中约 74% 是 2xx 访问日志，探针类路径只占 3.1%，`DEBUG` 与 `TRACE` 占 0.00%。所以主要杠杆是给成功请求上采样，其次才是删探针日志；调低 severity 门槛今天几乎收不到量。前五个服务的日志里 88.4% 是 2xx 访问日志行。

出站日志按条计费并占用 SigNoz 存储。Izumo 把 stdout 和 OTel 写成同一条 entry，所以「先打出来再说」等于直接买单。stdout 另有 Grafana Alloy 采集进 Loki，全量可查；OTel 这一路必须是精选的业务事件、`WARN` 和 `ERROR`，不是 stdout 的第二份拷贝。

## 边界

本 Skill 只裁定「哪条日志可以离开进程」，以及各服务怎样落地这条边界。它不裁定 trace 与 metric 的采样策略，也不产出看板；日志量核对与 dashboard 由 `$signoz-otel-dashboard` 承接。

`tcg-backend-doc/standards/go-core.md` §8 与 §9 已经规定：日志调用必须走 Izumo `pkg/log` 的 `log.Info/Warn/Error(ctx, ...)`，必须带 `ctx` 以关联 trace，`*zap.Logger` 由 Izumo 或 FX 注入，`X-Request-ID` 逐级透传，可观测性走 `launcher.OTelProvider` + SigNoz。本 Skill 不改动这些要求，只在其上补出站边界。

## 先分型：三种入口态

Izumo 的 `enableLogs` 默认关闭，只有 `launcher.OTelProvider(..., opentelemetry.WithEnableLogs(true))` 才导出日志。先读服务的 OTel provider 装配代码和部署侧 env，再选路线：

- A 全新：仓库里没有 `OTelProvider`，从零接入。按 [接入引导](references/bootstrap.md) 的 A，配置、日志、env、验收一次做齐，不要留噪音给以后治理。
- B 未开：有 `OTelProvider` 但缺 `WithEnableLogs(true)`，或部署侧有 `OTEL_LOGS_EXPORTER=none`。仓库里的噪音是潜在账单，按 [接入引导](references/bootstrap.md) 的 B 先清理、估量、再分阶段打开。在未清理的服务上先打开导出是成本事故，不是观测改进。
- C 已开：噪音正在计费，按 [采用清单](references/adoption-checklist.md) 逐项收敛。

## 必须出站

- `ERROR`：需要人介入或会触发告警的失败。必须带 `zap.Error(err)`，otelzap 会转成 `exception.message`、`exception.type` 和 stack。
- `WARN`：已经自愈但值得关注的事实——降级、重试、超时、回退、超过慢阈值的请求或 SQL、配置回退到默认值。
- `INFO` 业务事件：状态迁移与运行摘要，且必须携带业务 ID 和结果字段。例如订单创建、支付、发货；任务运行摘要（`processed`、`failed`、`elapsed_ms`）；消费批次摘要；配置热更新；进程启动与关停。

## 禁止出站

按现网实测量级排序，前两条决定成败：

- 未采样的 2xx 访问日志。成功请求已由 trace 和 RED 指标覆盖，只保留采样样本。采样率按流量分档，见 [配置基线](references/config-baseline.md)。
- 同一个请求的完整访问日志在网关和后端各记一次。当前分工是边缘保留带 `auth_user_id` 的那份，被代理的后端把 `sample_rate` 再降一档。
- 健康探针路径的访问日志：`/ping`、`/health`、`/healthz`、`/readyz`、`/livez`、`/metrics`，以及它们带业务前缀的别名。探针 handler 内部同样禁止打日志。
- cron、scheduler 与 dispatcher 的 tick：wake、run、schedule、心跳、keepalive、空轮询、「队列为空」。
- 循环内的 per-item、per-message、per-row `Info`，以及每次 RPC 或 LLM 调用的成功日志。
- 单个请求内的流程轨迹：`handler start`、`service step`、`handler end`、`handler result`。请求链路由 trace span 表达，不由日志表达。
- 每条 SQL。`database.debug: true` 会把每条 SQL 变成 `Info` 出站；要看 SQL 就开 trace span，不开 SQL 日志。
- 请求或响应 body、header 集合、Elasticsearch query DSL、SQL 语句原文、邮箱与用户名。`zap.Any("formData", ...)` 这类整体 dump 一律禁止。
- `DEBUG` 级别。本地 stdout 可以开，OTel 不出站。

## 常见误判

下面几条是现网最常见的错误分级，改起来最便宜：

| 现象 | 正确做法 |
| --- | --- |
| 业务 4xx 记成 `Error` | 业务校验失败是 `Warn` 或不记；`Error` 只留给需要人介入的失败 |
| 「best-effort，已忽略」记成 `Warn` | 明确忽略且无后续动作的失败记 `Debug` |
| tick、dispatch、poll 无条件记 `Info` | 用 `count > 0` 之类的门控，或者改成 metric |
| demo、hello、shadow-mode 探测日志留在生产 | 删除；它们经常占据空闲服务的全部日志量 |
| 在 Izumo access log 之上再写一份手写 access log | 删除手写的那份，配置 Izumo 的 |
| 给未清理的服务打开 `WithEnableLogs(true)` | 先清理再开 |

## 验收门槛

- 空闲 pod（无流量、无任务）的 OTel 日志速率必须为 0 条每分钟。
- 探针类路径的日志计数必须为 0。
- HTTP 服务的 2xx 访问日志条数必须不超过 `sample_rate` 乘以请求数。
- 位于循环、per-message 或 per-call 路径的日志必须降为 `Debug`、加工作量门控，或聚合成批次摘要。
- 上线前后各取 24 小时同口径对比，把降幅写进 PR。查询口径见 [验证方法](references/verification.md)。

## References

- [出站标准](references/standard.md)：判定级别语义、结构约束、字段词表、量化门槛与豁免流程时读。
- [Izumo 机制](references/izumo-mechanics.md)：确认日志怎样到达 OTel、access_log 与 GORM 的真实默认值、新旧版本能力差异、已知缺陷与不可信文档时读。
- [接入引导](references/bootstrap.md)：给全新服务从零接 OTel 日志，或给已接 trace 与 metrics 但从未打开日志导出的服务开开关时读。
- [配置基线](references/config-baseline.md)：为服务补 `access_log` 配置块、选采样档位和 gitops 环境变量时读。
- [采用清单](references/adoption-checklist.md)：在某个服务仓上逐步执行收敛并写 PR 时读。
- [验证方法](references/verification.md)：用 SigNoz 量改造前后的日志量，或核对某个服务的日志构成时读。
- [各技术栈落地](references/stacks.md)：目标不是 Go + Izumo 时读。
- [Collector 兜底](references/collector-backstop.md)：服务侧短期改不完，需要在 Collector 层丢弃噪音时读。
- [按仓库的整改清单](references/remediation-by-repo.md)：选择整改对象、确认某个仓已知问题、或寻找可复制的正面样例时读。
