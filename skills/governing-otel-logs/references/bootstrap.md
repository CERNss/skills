# 接入引导

`SKILL.md` 的出站边界是终态。本文管两种「日志还没进 SigNoz」的入口态：全新项目从零接入，以及已经接了 trace 与 metrics 但一直没打开日志导出。已经在出站的服务不看本文，直接走 [采用清单](adoption-checklist.md)。

两种入口态的共同前提：打开导出等于开始计费。先把仓库里已有的噪音清掉，再让它出站。

## 先定位入口态

在服务仓和 gitops 仓各扫一遍，代码与部署 env 两侧都要看：

```bash
rg -n 'OTelProvider|WithEnableLogs' --glob '*.go'
rg -n 'access_log' configs/
rg -n 'OTEL_SERVICE_NAME|OTEL_LOGS_EXPORTER' apps/<app>/envs/*/overlays/settings.yaml
```

| 现象 | 入口态 | 去哪 |
| --- | --- | --- |
| 没有 `OTelProvider`，gitops 里也没有 `OTEL_SERVICE_NAME` | A 全新 | 本文 [A](#a-全新项目从零接入) |
| 有 `OTelProvider`，但参数里没有 `WithEnableLogs(true)`，或部署侧有 `OTEL_LOGS_EXPORTER=none` | B 未开 | 本文 [B](#b-已接-trace-与-metrics日志导出从未打开) |
| 有 `WithEnableLogs(true)` 且部署侧没有 `OTEL_LOGS_EXPORTER=none` | C 已开 | [采用清单](adoption-checklist.md) |

三条注意：

- 「接了 OTel」不等于「日志在出站」。`defaultConfig` 里 `enableTracing` 与 `enableMetrics` 是 `true`、`enableLogs` 是 `false`（`pkg/opentelemetry/options.go:158-160`），所以 B 是现网最常见的形态，不是例外。
- `WithEnableLogs(true)` 也不等于在出站。含 hygiene 变更的 Izumo 起，部署侧 `OTEL_LOGS_EXPORTER=none` 会让 LoggerProvider 根本不构造，代码开着但一条也不出。
- SigNoz 里按 `service.name` 查不到该服务的日志，是 B 的旁证，取数口径见 [验证方法](verification.md)。

## A. 全新项目从零接入

主栈是 Go + Izumo。现网最干净的一份实现是 `tcg-pokemon`，下面每一步都可以照抄它。

### A.1 provider 装配

```go
launcher.OTelProvider(
    opentelemetry.WithEnableLogs(true),
    opentelemetry.WithFailFast(true),
),
launcher.HertzServerProviderV2(nil),
```

- 模型：tcg-pokemon `internal/app/api/provide.go:37-38`、`internal/app/worker/provide.go:25`。tcg-pokemon 只传了 `WithEnableLogs(true)`；`WithFailFast(true)` 是本引导在其基础上追加的（`pkg/opentelemetry/options.go` 已有该选项）。
- 不传 `WithServiceName`。service.name 是进程身份，由部署侧 `OTEL_SERVICE_NAME` 提供；写死在代码里会让所有环境上报同一个名字，gitops 也改不动它。约定是 `<repo>-<cmd 名>`，一个 `cmd/<name>` 一个 service.name，见 `tcg-backend-doc/skills/jhs-go-scaffold/references/infrastructure.md` §service.name。
- 业务代码要注入 `*appinfo.Info` 时补 `launcher.AppInfoModule()`。不补也不影响 service.name：provider 拿不到 `*appinfo.Info` 时内部回落到 `appinfo.New()` 自己读 env（`launcher/fast.go:253-259`）。
- `WithFailFast(true)` 让 exporter 初始化失败直接启动失败，而不是静默降级成 noop、上线后才发现什么都没出。
- HTTP 入口一律 `HertzServerProviderV2`。Izumo `README.md:139-144` 的 OTel 示例用的是已弃用的 `HertzServerTracerProvider` 加 `WithServiceName`，不要照抄那一段，理由见 [Izumo 机制](izumo-mechanics.md)。

### A.2 日志选项与级别

```go
fx.Provide(launcher.NewDefaultLogOptions()),
```

本地级别由 `LOG_LEVEL` 控制，OTel 出站门槛由 `OTEL_LOG_MIN_SEVERITY` 独立控制，两者默认都是 `info`，且串联生效——本地没打的日志不会出站。取值语义、非法值行为与优先级见 [Izumo 机制](izumo-mechanics.md)。

这两个变量只在含 `feat/otel-log-hygiene` 的 Izumo 上生效。新仓直接 pin 含该分支的版本，省掉后面一次升级和一次行为变更逐条核对。

### A.3 第一天就要带上的配置

新服务补三处，不要留到「以后治理」：

- `access_log` 块：抄 [配置基线](config-baseline.md)，按预估请求量选采样档。探针的带前缀别名（例如 `/api/v8/pokemon/healthz`）要逐条列进 `excluded_paths`；tcg-pokemon 现网唯一的缺口就是漏了这两个别名。仓库的 `configs/config.tmpl.yaml` 与 nacos 副本 `configs/nacos/<service>.yaml` 两份都要写，只写前者对已部署环境无效。
- `database`：非本地环境 `debug: false` 加 `enable_tracing: true`，取值同 [配置基线](config-baseline.md)。要看 SQL 就看 span。
- 探针：worker 与 consumer 用裸 `net/http` mux（模型 tcg-base `internal/app/worker/health.go:17-21`）或 `launcher.AdminHertzModule`（`launcher/fast.go:218`）开独立管理端口；HTTP 服务把探针挂在业务端口上时靠 `excluded_paths` 排除。探针 handler 内部一条日志都不打，模型 tcg-pokemon `internal/app/api/health.go`。

scaffold 生成的探针模板（`tcg-backend-doc/skills/jhs-go-scaffold/references/business.md:1172`）会在探针里打 `Info`，生成后删掉那一行。

### A.4 第一批业务日志怎么写

- 调用形态一律 `log.X(ctx, msg, fields...)`：`msg` 是稳定常量，变量全部进字段，业务 ID 用统一字段名。级别语义、结构约束与字段词表见 [出站标准](standard.md)，新增字段前先在词表里找同义项。
- 错误带 `zap.Error(err)`，否则 SigNoz 里没有 `exception.*` 字段。
- 循环、per-message、per-row 路径上确实要在本地看的记录加 `log.Loop()` 标记，本地留、不出站。
- worker 与 consumer 的默认形态是「做了事才记」的批次摘要，写法与模型见 [各技术栈落地](stacks.md)。
- 起步阶段一个入口有 5 到 10 条业务日志就够。新服务最常见的错误不是漏记，是把一个请求的 start / step / end 全记一遍——那是 trace span 的职责。

### A.5 部署侧环境变量

env 由 gitops overlay 注入，不写进 YAML 配置。nacos 起草与发布、gitops envs 脚手架、vault 引用清单走 `jhs-service-deploy`，本文只给日志相关的取值。

| 变量 | 必填 | 取值 |
| --- | --- | --- |
| `OTEL_SERVICE_NAME` | 是 | `<repo>-<cmd 名>`，例 `tcg-pokemon-api` |
| `OTEL_EXPORTER_OTLP_ENDPOINT` | 是 | CN 集群 `grpc://signoz-otel-collector.monitoring:4317` |
| `OTEL_EXPORTER_OTLP_PROTOCOL` | 是 | `grpc` |
| `OTEL_RESOURCE_ATTRIBUTES` | 是 | `service.namespace=<repo>,deployment.environment=<env>,cloud.region=cn` |
| `LOG_LEVEL` | 否 | 默认 `info`，不设即可 |
| `OTEL_LOG_MIN_SEVERITY` | 否 | 默认 `info`，不设即可；只在噪音大的存量服务上临时设 `warn` |
| `OTEL_LOGS_EXPORTER` | 否 | 不设。设 `none` 是停止出站的回滚开关 |

样例以现网 `cern-gitops` 为准，`apps/tcg-pokemon-api/envs/{testing,prod}/overlays/settings.yaml` 是最新的一份完整形态。两条与既有文档不一致的事实，按现网和代码走：

- `OBSERVABILITY_REPO.md` 的命名约定写 `service.namespace=tcg` 与 `service.version=<version>`。现网 overlay 里 `service.namespace` 一律按仓库取（`tcg-deck`、`tcg-base`、`tcg-pokemon`……），且没有任何一份带 `service.version`（2026-09 抽查）。
- 同一文档写 Izumo 的读取优先级是 `APP_NAME > OTEL_SERVICE_NAME`。代码相反：`appinfo.New()` 先读 OTel env，legacy `APP_NAME` 只填补留空的字段（`pkg/appinfo/appinfo.go:175-190`）。新服务只设 `OTEL_SERVICE_NAME`。

`LOG_LEVEL` 与 `OTEL_LOG_MIN_SEVERITY` 今天在 cern-gitops 的 Go 服务里一处都没有出现——含 hygiene 变更的 Izumo 尚未发版。新服务用默认值，需要临时压量时再加。

### A.6 首次上线验收

四条，缺一条就不算接完：

1. 本地起服务，连打十次探针，stdout 必须不出现访问日志：`for _ in $(seq 10); do curl -s -o /dev/null http://127.0.0.1:8080/healthz; done`
2. 手工跑一次典型业务调用，数 stdout 里的日志条数，与设计时的预期逐条对上。多出来的通常是轨迹日志，或第三方库的默认 logger。
3. testing 跑满 24 小时，按 [验证方法](verification.md) 取 `service.name` 计数与 severity 构成，再抽一段原始样本确认访问日志占比。这个数就是该服务后续的对比基线，写进 PR。
4. 空闲副本（无流量、无任务）的 OTel 日志速率为 0 条每分钟。不为 0 一定是 tick、心跳或探针，回到 A.3 与 A.4。

### A.7 非 Go 栈

Python、Node、Convex、Deno、nginx、PHP 的落地位置见 [各技术栈落地](stacks.md)。本文 A.3 到 A.6 的顺序不变：先配置、再日志、再 env、最后验收。

## B. 已接 trace 与 metrics，日志导出从未打开

### B.1 判定

三个信号任意一个成立即为 B：

- 代码里有 `launcher.OTelProvider(...)`，参数里没有 `opentelemetry.WithEnableLogs(true)`。
- 有 `WithEnableLogs(true)`，但部署侧 env 有 `OTEL_LOGS_EXPORTER=none`。
- provider 根本没走 `launcher.OTelProvider`，例如自己拼 exporter 只建了 TracerProvider。

已确认属于 B 的现网仓见 [按仓库的整改清单](remediation-by-repo.md)：tcg-card、tcg-data-task、tcg-data-engine 的全部 6 个入口、tcg-deck deckfill-trainer、tcg-price-crontab、tcg-price-engine、tcg-price-service。

### B.2 打开之前的门禁

硬规则：先清理，再打开。放在同一个 PR 里可以，但清理必须排在开关前面。

1. 按 [采用清单](adoption-checklist.md) 第 3 步到第 8 步做完噪音清理：探针 handler 日志、热路径 `Info`、tick 与 per-item、`database.debug: true`、payload dump、缺 `ctx`。
2. 估算打开后的量级：热路径 `Info` 调用点数乘以对应的请求量或消息量，加探针路由数按 [出站标准](standard.md) 的换算基准折算，加访问日志按采样后的条数。估不出来说明第 1 步没做完，不要开。
3. 两个反例（细节见 [按仓库的整改清单](remediation-by-repo.md)）：tcg-data-engine 六个入口全部缺 `WithEnableLogs`，同时 grading-price-sync 系列同步器有 325 处 `Info`，含 `[timing]` 与 banner 行；tcg-price-crontab 有 576 处日志调用，逐行 `Info` 和每 2000 行一条的进度日志都在。这两个仓今天不出站，直接打开开关就是账单事故，不是观测改进。

### B.3 分阶段打开

1. testing 先开：代码加 `WithEnableLogs(true)`，env 保持默认 `OTEL_LOG_MIN_SEVERITY=info`。跑满 24 小时，按 A.6 的四条验收。
2. 实测量级与 B.2 的估算差一个数量级时回到 B.2，不要靠调门槛掩盖。
3. prod 首周可以先 `OTEL_LOG_MIN_SEVERITY=warn` 起步，量级确认后再降到 `info`。这是闸门不是终态，撤回时间写进 PR。
4. 回滚开关是 `OTEL_LOGS_EXPORTER=none`：改 env 即可停止出站，不必回滚镜像。前提是 Izumo 已升到含 `feat/otel-log-hygiene` 的版本，旧版本没有这个开关，只能改代码回滚。

env 改动与发布流程走 `jhs-service-deploy`。

### B.4 验收

同 A.6 的四条，再加一条：打开当天与打开前一天取同口径的 SigNoz 全量计数，确认新增量与 B.2 的估算在同一量级。

## C. 已经在出站

直接走 [采用清单](adoption-checklist.md)。
