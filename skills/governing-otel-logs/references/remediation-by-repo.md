# 按仓库的整改清单

审计结论快照，用于挑整改对象和确认某个仓的已知问题。行号是当时的观察结果，动手前复核一次。清单只列已确认的问题，不代表该仓没有别的问题。

## 优先级

按 SigNoz 实测日志量排（24 小时占比）：

| 顺序 | 服务 | 占比 | 主要来源 |
| --- | --- | --- | --- |
| 1 | tcg-trade（product、user、auction、cart、inventory、seller 六面） | 79.2% | 未采样 2xx 访问日志 + 每请求轨迹日志 |
| 2 | tcg-gateway-http | 8.9% | 已采样 0.1，仍是第四大；与后端重复记录 |
| 3 | tcg-deck | 1.5% | 未配置 access_log |
| 4 | tcg-crawler-preprocess-consumer | 1.3% | per-message Info |
| 5 | tcg-ai-eye | 1.3% | 每次识别 11 条 Info + payload dump |
| 6 | tcg-search-worker | 1.2% | 每次搜索输出完整 query DSL |
| 7 | tcg-base-im | 0.6% | 见下方 tcg-base |

tcg-trade-product 一家占 38.1%（3270 万条），tcg-trade-user 占 23.8%（2040 万条）。先做这两个。

## Go + Izumo 现网服务

### 舰队级事实

16 个 Go 服务的抽样结果：15 个记录未采样 2xx，13 个不排除探针路径，1 个用了采样，4 个完全没有导出日志，0 个用了 zap sampler 或按模块设级别，13 个没有不改代码就调整日志级别的手段。Izumo 版本跨度 v0.4.3 到 v1.5.0-beta.3，trace 关联率随版本递增。v1.5.0-beta.3 就是当前 `master`，含 hygiene 变更的版本尚未发布，所以舰队里没有任何仓已经拿到新的 access log 默认档。

7 个仓共 17 处探针 handler 复制了同一段代码：

```go
log.Info(ctx, "ping", zap.String("time", time.Now().String()))
```

纳秒时间戳让每条 ping 日志都不同，dedup 和聚合全部失效。分布：tcg-trade 9 处、tcg-saas 2 处、tcg-wiki 2 处，tcg-identity、tcg-idlinker、tcg-payment、tcg-price-crontab 各 1 处。约 28 条探针路由没有 `excluded_paths`，按 10 秒探测一次估算每天约 48.4 万条访问日志。

### 高优先级

| 仓库 | Izumo | 已确认问题 |
| --- | --- | --- |
| tcg-trade | v1.5.0-beta.3 | 9 个 `/ping` handler 全部打日志（`internal/app/*/router.go`：seller:53、order:58、auction:79、activity:51、payment:50、user:97、product:96、inventory:69、cart:48）；`internal/app/job/dispatcher.go:126,135` 对 79 个每分钟 cron 记「开始执行 / 执行完成」，约 22.8 万条每天，而 `:92-96` 的区域过滤在记日志之前就返回了，同一个门控应前移；`consumer/queue_basic.go:31,105,192,222` 记「队列为空，无需处理」；`auction_product_detail.go:1178,1198,1234` 每次详情请求 3 条 Info 含 `zap.Any` 结果摘要；`activity/middleware/verydata.go:58` 每请求 dump header 与 body；1318 处 `Warn`（其中 823 处在 `internal/app/job`）含「best-effort，已忽略」；约 1198 处调用没有 `ctx` |
| tcg-identity | v1.2.0 | `internal/service/user-geo-pipeline.go:439` 影子模式每用户每轮一条 Info，约 15 万条每轮，`configs/nacos/tcg-identity-worker-config.yaml:43` 的 `shadow: true` 在线上；`user-geo-backfill.go:237` 同型；`http/router.go:104-105` ping 日志；`configs/nacos/tcg-identity.yaml:13,22` `debug: true` 已部署；`middleware/error.go:31` 把业务 4xx 记成 `Error` 并 `zap.Any` 整个错误切片 |
| tcg-payment | v1.5.0-beta.2 | `configs/nacos/tcg-payment-http-config.yaml:22` 与 `tcg-payment-rpc-config.yaml:23` 都是 `debug: true` 且已部署，另有 `internal/source/payment-pg.go:125,138` 代码里再开一次；`router.go:44-45` ping 日志；四个 30 秒 dispatcher 在 `count = 0` 时仍无条件记录（`channel_compensation.go:1342,1391,1447`、`payment_auto_close.go:175`，约 1.15 万条每天每副本）；`recon.go:1497` 非 leader 每 5 分钟一条；`channel_notify.go:564` 与 `merchant_notify_dispatch.go:660` 内嵌完整请求与响应体；`interaction_log.go:115` 在 access log 之外再记一条每调用日志。`ctx` 覆盖率 96%，是全舰队最高的 |
| tcg-wiki | v1.5.0-beta.2 | `internal/repository/phpmysql.go:44` 的 slog 适配器停在 Debug，产生约 30 条每查询的「Successfully queried」；`:475,:733` 用 `fmt.Println` 直接打原始 SQL，`:476,:478` 链式 `.Debug()`；`http/middleware/auth.go:86` 每个已认证请求一条 Info 且带用户名；`match-rule/service/event-handler.go:178-341` 一分钟轮询即使 0 条也记 4 到 6 条 Info；`handlers/psa-jp-card.go:342-373` 每分钟 6 处 `fmt.Println` 含两处 `ToSQL` dump；`match-rule/router.go:19` 与 `http/router.go:86` ping 日志 |

### 中低优先级

| 仓库 | Izumo | 已确认问题 |
| --- | --- | --- |
| tcg-search | v1.2.0 | `app/search/handler.go:2311` 每次卡牌搜索输出完整 Elasticsearch query DSL；同义词与 AB 分支再加 1 到 4 条 Info；hlog 只支持 printf，没有结构化字段 |
| tcg-saas | v1.2.0 | 全仓只有 6 处 Info，其中 2 处是 ping（`api/router.go:32`、`admin-api/router.go:32`），2 处是 hello 演示端点，稳态日志量接近全部是废量 |
| tcg-idlinker | v1.3.0-rc.6 | `idlinker-http/router.go:51-52` ping 日志；`consumer/handler/psa/handler.go:60` 与 `card_data_import.go:83` 每条 Kafka 消息记跳过；`idlinker-anno/auth.go:158` 记录邮箱；`ctx` 覆盖率 7% |
| tcg-inventory-sync 与 third-party-inventory-sync | v1.1.0 | 热路径用标准库 `*log.Logger`（`runtime.go` 注入 `log.Default()`），无级别、无 trace、绕开 OTel；`idlinker-poll.go:90` 与 `:84` 在全零轮次仍触发；`platform/worker/consumer.go:151` 每条 Kafka 消息一条；四个消费循环在 `for` 里 `continue` 且不退避，broker 故障时会打成风暴；配置里的 `log_level` 是死配置 |
| tcg-kefu-backend | 非 Izumo | `net/http` + slog JSON。`internal/httpapi/router.go:87` 手写 access log 包住整个 mux 且没有 skip list（`requestLog` 在 `:1358-1364`，探针在 `:292-294`）；`agent/client.go:193` 每次 LLM 调用一条；`ws.go:108` 每次断连一条；slog 不带 `ctx`。需要先定技术栈，不是改配置 |
| tcg-price-crontab | v1.0.0 | 尚未导出，576 处日志调用。`jobmanager/manager.go:234,309,296` 每次执行 2 条 Info；`syncer/jp_kafka_consumer.go:797` 每 2000 行一条；`cn_dws_to_legacy_mysql.go:998,1034` 逐行 Info；`jp_kafka_consumer.go:165` 把 kafka-go 的 ErrorLogger 接到 Info |
| tcg-price-engine | v1.2.0 | 尚未导出。`middleware/access_log.go:19-30`（注册于 `router.go:69`）在 Izumo access log 之上再写一份；`/ping` 与 `/healthz` 都无排除；`listing_min_price.go:369,398,430,461` 每页一条 Info；`ctx` 覆盖率 0%；配置里的 `log.level` 是死配置 |
| tcg-price-service | v0.4.3 | 尚未导出。`price_service.go:824` 每次缓存未命中刷新一条；`consumer.go:157` 在 PG 持续故障时每分钟 30 条重试日志；两条 ping 路径 |
| tcg-market-quote | v1.1.0 | `config_sync_service.go:605` 逐条报价进度；手写 `gorm.Open` 未设 `Logger`，`debug: true` 键无效，同时也没有 SQL span |
| tcg-grade-service | v1.1.0 | 全舰队最干净。仅两条探针路由的 access log；`middleware/crypto.go:37` 在解密失败时记录完整原始请求体；`ctx` 覆盖率 5% |

### 第一批扫描确认的其他仓

- 默认 access log、无配置块：tcg-admin-api、tcg-ai、tcg-binder、tcg-card-binder、tcg-card、tcg-data-engine、tcg-data-task、tcg-deck（高流量）。
- `/ping` handler 记 Info：tcg-ai `internal/app/eye/router.go:45`、tcg-bandai-deck `router.go:38`、tcg-binder `http/router.go:73` 与 `tmarket/router.go:67`、tcg-card-binder 三条 ping 路由（`router.go:215` 的 `handlePing`、`worker/router.go:31`）、tcg-deck `api/router.go:82`、tcg-data-engine idlinker-http `router.go:35`。
- 部署态 `database.debug: true`：tcg-admin-api `configs/nacos/tcg-admin-api-config.yaml:47,56,65`、tcg-bandai-deck `configs/config.tmpl.yaml:14`、tcg-data-engine `configs/config.tmpl.yaml:4,11,18,116`。
- payload dump：tcg-ai `internal/service/card_recognition_impl.go:1176`（formData）与 `:1205`（response）、`internal/app/eyerpc/proxy.go:82`，每次识别请求 11 条 Info。
- per-message 与 per-item Info：tcg-crawler-preprocess `handlers/crawler-data-handler.go:133,248`；tcg-binder `service/order-import.go:423`、`holding.go:449`；tcg-data-task `repository/wiki_repo.go:106`（每次 RPC 成功）；tcg-base `internal/app/rpc/content_check_handler.go:108,153`、`profit_sharing_admin_handler.go:482`；tcg-data-engine grading-price-sync 系列同步器共 325 处 Info，含 `[timing]` 与 banner 行。
- 缺 `WithEnableLogs`，日志尚未到达 OTel：tcg-card、tcg-data-task（Izumo v0.4.3）、tcg-data-engine 全部 6 个入口、tcg-deck deckfill-trainer、tcg-price-crontab、tcg-price-engine、tcg-price-service。这些仓必须先清理再打开开关。
- 缺 `ctx`：tcg-auction（0/9）、tcg-data-task（2/25）、tcg-card（2/49）、tcg-binder 约 50%。

### tcg-base 试点

Izumo v1.4.0-beta.6，六个入口全部 `WithEnableLogs(true)`，全仓没有任何 `access_log` 配置块。`debug: true` 出现在 `configs/config.tmpl.yaml:13` 和五份 nacos 配置（http:21、rpc:24、worker:25、match:27、file:40）。每请求 Info：`push_handler.go:82`、`matcher.go:1106`、`combine_make_native.go:448`、`rpc/content_check_handler.go:108,153`、`profit_sharing_admin_handler.go:482`。循环内 Warn：`direct_preview.go:494`、`combine_make_native.go:1556`。试点分支 `chore/otel-log-hygiene` 在并行准备中。

## 非 Go 与其他仓

26 个仓的审计结论：Go 与 Izumo 之外，问题基本是潜伏的。今天只有 crawler-scheduler 和 convex-otel-sidecar 向 SigNoz 出站日志，ai-lab 出站到 Pydantic Logfire。是否把 Logfire 并到 SigNoz 是策略决定，本 Skill 只记录不裁决。这些仓必须在接入 OTel 之前先满足标准，否则接入当天已知噪音直接变成账单。

| 仓库 | 状态 | 已确认问题 |
| --- | --- | --- |
| crawler-scheduler | Go + Izumo v1.5.0-beta.3，已出站 | `scheduler.go:324` 与 `:615` 每 30 秒扫描无条件 2 条 Info，空闲每副本约 5800 条每天；`root-config.go:339` 的 `zap.RedirectStdLog` 把 70 处 `log.Printf` 强制成 INFO，含正文以 `WARN` 前缀开头的行；access log 无过滤，`/ping` 与 `/readyz` 都记录；零 `CtxLog`，没有 `trace_id` |
| convex-otel-sidecar | Go OTLP 生产者，已出站 | `exporter.go:100` 对静默成功的执行不发摘要，`emitAllCompletions=false`，这是正面样例。缺口：`:115` 在执行已有日志行时重复发一条 INFO 摘要；没有 severity 下限，Convex 的 DEBUG 被原样转发；没有 `trace_id` |
| ai-lab | Python，出站到 Logfire | `apps/eye` 每次图搜约 7+N 条 INFO（`serve/search_v3.py:919,992,1054,1236,1905`），`:745` 输出完整候选打分数组，`:1912` 把整个响应体放进 span attribute；14 处 `instrument_fastapi` 带 `capture_headers=True` 且无 `excluded_urls`，30 秒健康检查产生每 pod 每天 2880 个 span；`apps/spider/common/observability.py:78` 把 LogfireLoggingHandler 挂在 root logger 的 INFO 上，强制转发 1155 处 `log.info`，含 `crawl_bcg_list_spider.py:63` 的整条数据；`packages/core/config.py:43` 的 `configure_logfire(is_console=True)` 把每条日志按 DEBUG 再打一遍 stdout。正面样例：`apps/tcgen/entrypoint.py:24` 的 `EXCLUDED_URLS` |
| tcg-convex | Convex，未接 OTel | `convex/companyRpc/transport.ts:173,219` 每次网关 RPC 一条 `console.info`，共 35 处；丢弃了网关传来的 trace id。`docs/company-rpc.md` 是公司唯一一份成文日志约定，可作 Convex 侧模板 |
| customer-service-feedback-platform | Izumo，未出站 | `internal/platform/im.go:115` 每条外发消息 dump 完整 IM 请求体 |
| micro_jihuanshe-deck-mbti | Izumo v1.0.0，两个模块，未接 OTel | `host/docker-compose.yaml:40,64` 每 10 秒 curl `/ping`，两个服务各约 8600 条访问日志每天，业务流量接近零。补 `excluded_paths` 即可 |
| riftdeck_backend | Go + Hertz + GORM，未接 OTel | `internal/source/postgres.go:23` 用 GORM 默认 logger（`IgnoreRecordNotFoundError=false`、`Colorful=true`），配合 `metagame.go:319-339` 每请求制造 N×M×K 次「查不到」，全部变成带完整 SQL 和 ANSI 转义的 ERROR。一旦接入就是高危 |
| tcg-one-convex 与 harness-runtime | Convex | `convex/http.ts:9` 每条聊天消息以 500ms 轮询最多 120 秒，最多 240 次执行；`/streamMessage` 连错误都不记；`worker/runtime.ts:2428` 把 tick 错误吞进变量从不记录。是盲区不是噪音 |
| tcg-ygo 与 mycard-replay-recorder | Deno 2 | 9 个生产 systemd unit 全部带 `--log-driver none`，日志直接销毁；内置 OTel（`OTEL_DENO=1`）未启用；`setInterval(emitMetrics, 60000)` 空闲时每分钟输出一个大对象 |
| six-prize-forge | Bun CLI + systemd timer | 212 处 console 调用集中在 `tools/`，含多 KB 的 JSON dump（`reference-decks/sync-convex.ts:475,644`）；目前只进 journald |
| wxygo-svr | Laravel 5.4 / PHP 5.6 | 所有 `Log::` 重绑到 Bugsnag；PHP 5.6 无法用 opentelemetry-php；`RedisDistributedLock.php:55,151` 在每次竞价与鉴权的加解锁热路径记 `Log::info`；`APP_LOG_LEVEL` 默认 `debug`。按豁免条款处理 |
| tcg-notes | Node `node:http` | 完全没有访问日志，只记 5xx 且非结构化 |
| tcg-identity-platform | nginx | 默认配置记录根路径下每个 2xx 与探针请求 |
| pkm-deck-mbti-bff、seatunnel-cdc-manager | Izumo | access log 无过滤，量低。seatunnel-cdc-manager 的 `provide.go:50` 把 `WithServiceName` 写成了 `seatunnel-cdc-manger`，SigNoz 里按错误名归组 |

不需要处理：reader、ops-workbench、send-to-grade、questionnaire、jihuanshe_lite_shell_app、tcg-one-convex-and-pi-agent-core（零日志）。这些是客户端应用、CLI 或桌面程序，不产生服务端日志。

## 可复制的正面样例

| 场景 | 样例 |
| --- | --- |
| 完整 access_log 配置 | tcg-pokemon `configs/nacos/tcg-pokemon.yaml:16-19` |
| 边缘服务采样 + `auth_user_id` tag | tcg-gateway `configs/config.tmpl.yaml` |
| 代码里设排除路径 | tcg-inventory-sync `internal/app/webhook/router.go:31`、third-party-inventory-sync `webhook/router.go:30` |
| 裸 net/http 探针 | tcg-base `internal/app/worker/health.go:17-21`、tcg-identity `worker/probe.go:33` |
| 只记 `status >= 400` | rotom `internal/authserver/http.go:81` |
| 访问日志前的探针跳过 | auto-reviewer `internal/httpapi/auth.go:309` |
| 做了事才记 | tcg-card-binder `order_event_inbox_worker.go:121` |
| 定时器出 metric 不出日志 | tcg-idlinker `consumer/stats.go` |
| 批量消费零 per-message 日志 | tcg-price-service consumer，500 条或 1 秒成批 |
| 每轮只取一个样本 | tcg-search `internal/logbridge/hlog.go:251-259` 的 `sampleLogged` 与本地 `OTEL_LOGS_EXPORTER=none` 开关 |
| per-message 用 Debug | tcg-crawler-preprocess |
| 已硬化的 `debug: false` | tcg-crawler-preprocess |
| 静默成功不发摘要 | convex-otel-sidecar `exporter.go:100` |
| Python 排除探针 URL | ai-lab `apps/tcgen/entrypoint.py:24` |
| 成文的日志约定 | tcg-convex `docs/company-rpc.md` |

## 待补充

- SigNoz 服务级占比需要在每轮整改后重新取数，本清单的百分比是 2026-09-02 的快照。
- tcg-backend-doc `skills/jhs-go-scaffold/references/business.md:1172` 的探针模板会打 Info，需要单独提 PR 修模板，否则新服务持续复制这个缺陷。
- Logfire 与 SigNoz 是否合并到一个后端，尚未决定。
