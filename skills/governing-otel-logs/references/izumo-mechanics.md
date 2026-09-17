# Izumo 机制

判定某个 Go 服务的日志为什么会出站、怎样才能不出站时读本文。

行号来自 Izumo `master`（`905bca9`，即 tag `v1.5.0-beta.3`）。日志治理相关的改动在分支 `feat/otel-log-hygiene`（`15cc30a`，master 上的一条提交）里，尚未发版，本文分两侧写：先确认目标仓 pin 的是哪一侧，再往下用。改动前按当前 checkout 复核一次行号。

## 日志怎样到达 OTel

```text
业务 log.Info(ctx, ...) → zap Core → otelzap bridge → OTLP → Collector → SigNoz
                                  ↘ stdout（同一条 entry）
```

`AttachOtelLogBridge`（`pkg/log/zap.go:338`）用 `zap.WrapCore` 挂上 `otelzap.Core`。stdout 和 OTel 是同一条 entry 的两个出口，不是两套开关。因此「只在本地看看」的日志一旦被打出来，就已经出站。

`zap.Error(err)` 经 otelzap 转成 `exception.message`、`exception.type` 和 stack；不带 `zap.Error` 的错误日志在 SigNoz 里查不到异常字段。

## 导出开关

日志导出由 `enableLogs` 控制，默认关闭（`pkg/opentelemetry/options.go:160`），必须显式打开：

```go
launcher.OTelProvider(
    opentelemetry.WithEnableLogs(true),
)
```

`WithEnableLogs` 定义在 `pkg/opentelemetry/options.go:364`。HTTP server 装配走 `launcher.HertzServerProviderV2`（`launcher/fast.go:35`）；`launcher.HertzServerTracerProvider`（`launcher/fast.go:23`）已弃用。不存在 `HertzOTelProvider` 这个入口，看到这个名字说明文档或记忆有误。

分型时还要看部署侧 env：含 hygiene 变更的版本起，`OTEL_LOGS_EXPORTER=none` 会让已经写了 `WithEnableLogs(true)` 的服务不再构造 LoggerProvider，代码开着但实际没有出站。

## access log 在已发布版本里的真实默认值

`pkg/httpserver/config.go` 在 `master` 上的形态：

| 事实 | 位置 | 后果 |
| --- | --- | --- |
| `AccessLog` 默认启用 | `:86` | 不写配置块也会记录 |
| 配置键为 `disable`、`format`、`sample_rate`、`always_log_errors`、`excluded_paths` | `:118`-`:123` | 只有这五个键，写别的键不生效 |
| `applyDefaults` 不给 access log 填任何默认值 | `:229` | `excluded_paths` 为空，探针路径全部记录 |
| `sample_rate` 存储默认值是 `0` | `:121` | `0` 与 `1` 都表示不采样，即每个请求都记录；`Validate` 拒绝大于 1 的值 |

`sample_rate` 的默认值是 `0` 而不是 `1.0`。按「默认 1.0」写的校验或迁移脚本会判错。含 hygiene 变更的版本把这张表整个改掉，见下面的 access log 配置与默认值。

access log 记录带 `attributes["type"] == "http.HertzHttpServer"`（`pkg/httpserver/hertz.go:68`、`:191`），body 形如 `200 - 66.5ms GET /path`，格式串是 `${status} - ${latency} ${method} ${path}`。在 SigNoz 里靠这个 attribute 把访问日志和业务日志分开，也靠它写 Collector 侧的丢弃规则。

## GORM 与 SQL

`pkg/database/gorm.go`：

- `Debug bool`（`:41`）在 master 上没有显式 yaml tag，靠字段名静默绑定到配置里的 `debug`。改配置结构时容易失手；hygiene 变更把 `yaml:"debug"` 显式写了出来，绑定行为不变。
- `o.Debug` 为真时 `zapGormLogger.LogMode(logger.Info)`（`:126`）并额外 `db.Debug()`（`:146`），每条 SQL 连同绑定参数都是一条出站 `Info`。
- 默认 logger 是 `zapgorm2`，`IgnoreRecordNotFoundError = true`（`:120`），慢阈值取 zapgorm2 默认 100ms，超阈值记 `Warn`。

要观察 SQL 就打开 trace（SQL span），不要打开 `debug`。

## 健康探针的正确位置

探针必须走不经过 access log 中间件链的路径：

- 裸 `net/http` mux 单独监听。模型：tcg-base `internal/app/worker/health.go:17-21`。
- 或者 `launcher.AdminHertzModule`（`launcher/fast.go:211`）开独立管理端口。

Izumo README 的 quick-start 在业务端口上注册 `/ping`（`README.md:85`、`:131`），现网多数仓库是从这里复制的。不要把它当成推荐形态。

## 含 hygiene 变更的版本新增的能力

分支 `feat/otel-log-hygiene` 新增下列契约名。旧版本没有这些能力，只能靠删代码和改 `access_log` 配置收敛；要用这些能力必须把 Izumo 升到含 `feat/otel-log-hygiene` 的下一个 beta。

变更说明写在 Izumo `docs/changelog/` 的草稿里。草稿文件名只是占位（同名 tag 已经存在），最终版本号由 Izumo 自己的发版流程决定。不要在 PR、配置注释或本 Skill 里写死一个版本号，写「含 `feat/otel-log-hygiene` 的下一个 beta」。

### 环境变量

| 变量 | 值域 | 作用 | 非法值 |
| --- | --- | --- | --- |
| `LOG_LEVEL` | zapcore 级别名，大小写不敏感：`debug`、`info`、`warn`、`error`，另接受 `dpanic`、`panic`、`fatal` | 本地级别，默认 `info` | stderr 打一条 `Warn` 后按 `info` 走，不阻断启动 |
| `LOG_FILENAME` | 文件路径 | 非空时设 `Options.Filename` 并把 `Stdout` 切到 `StdoutBoth`（stdout 加文件），容器采集不会因为改成写文件而断流 | — |
| `OTEL_LOG_MIN_SEVERITY` | 同 `LOG_LEVEL` | OTel 出站门槛，默认 `info`，与本地级别解耦 | 保持 `info` 并 `Warn` 一次 |
| `OTEL_LOGS_EXPORTER` | 只认 `none`，大小写不敏感 | `none` 表示不构造 LoggerProvider，即使已经传了 `WithEnableLogs(true)`。只关不开，其余取值维持现状 | — |
| `IZUMO_ACCESS_LOG_EXCLUDED_PATHS` | 逗号分隔路径 | 整体替换 `excluded_paths`，不是追加；设为空串表示显式退出排除 | — |
| `IZUMO_ACCESS_LOG_SAMPLE_RATE` | `(0, 1]` 的浮点数 | 覆盖 `sample_rate` | `0`、超出范围和解析失败一律忽略并告警，保留原值（以 Izumo 修订后提交为准） |

`LOG_LEVEL` 与 `LOG_FILENAME` 由 `log.DefaultOptions()` 解析，走 `launcher.NewDefaultLogOptions()` 或直接调用都生效。`OTEL_LOG_MIN_SEVERITY` 在 `AttachOtelLogBridge` 里解析，所有挂过 bridge 的路径都生效。

优先级是「代码显式 > env > 配置文件 > 框架默认」。access log 的两个 `IZUMO_` 变量是例外：它们在 `applyDefaults` 里应用，晚于调用方构造 `Options`，所以连代码里写死的值也会被盖掉。这是刻意的，部署侧要能不改代码压日志量。

两个容易踩的点：

- 本地级别是外层闸。只设 `OTEL_LOG_MIN_SEVERITY=debug` 不会让 `DEBUG` 出站，还得 `LOG_LEVEL=debug`；反过来只设 `LOG_LEVEL=debug` 也不会，出站门槛独立且默认 `info`。
- `IZUMO_ACCESS_LOG_SAMPLE_RATE` 不是用来关访问日志的。它只接受 `(0, 1]`，`0`、超范围和解析失败都会被忽略并告警、保留原值。要彻底关掉访问日志写 `access_log.disable: true`。（以 Izumo 修订后提交为准）

### 代码 API

- `log.SetOTelMinLevel(zapcore.Level)` 与 `log.OTelMinLevel()`：设置和读取出站门槛。`Set` 只在 bootstrap 调一次，调用后会钉死取值，`OTEL_LOG_MIN_SEVERITY` 不再生效。
- `log.SetOTelDropRule(func(zapcore.Entry) bool)`：返回 `true` 的记录不出站；传 `nil` 清除，后一次调用替换前一次。它在热路径上对每条通过门槛的日志求值，判断必须廉价，用 `ent.LoggerName` 上的 switch 或 map 查找，不要现编 regexp。
- `log.Loop()` 与 `log.LoopMarkerKey`：zap field 标记，键为 `_loop_`。OTel 分支整条丢弃，本地分支保留记录并把标记字段本身剥掉。写在调用处和 `logger.With(log.Loop())` 绑定两种形式都生效，`Warn` 与 `Info` 都拦得住。用于循环内那些确实要在本地看、但严重级别门槛拦不住的记录。没有挂 OTel bridge 的 logger 不做剥离，标记字段会留在本地输出里。
- `httpserver.HygieneAccessLogDefaults()`：返回未配置服务最终生效的 `AccessLogConfig` 副本，可以在它上面改字段当起点。
- `httpserver.DefaultAccessLogExcludedPaths()`：返回默认探针路径副本，用 `append(httpserver.DefaultAccessLogExcludedPaths(), "/custom")` 拼自定义清单。
- `mq.NewKafkaErrorLoggerAdapterWithContext(ctx, logger)`：新增，按 `Error` 输出，接 kafka-go 的 `ErrorLogger` 槽位。原有的 `NewKafkaLoggerAdapter` 与 `NewKafkaLoggerAdapterWithContext` 接 `Logger` 槽位，级别由 `Info` 降为 `Debug`。

### access log 配置与默认值

`applyDefaults` 现在会给 access log 填默认值，没写配置块的服务直接进入治理档：

| 配置键 | 类型 | 默认值 | 显式退出写法 |
| --- | --- | --- | --- |
| `excluded_paths` | `[]string` | `/ping`、`/health`、`/healthz`、`/readyz`、`/livez`、`/metrics` | `excluded_paths: []` |
| `excluded_prefixes` | `[]string` | 空，不做前缀排除 | — |
| `always_log_errors` | `*bool` | `true` | `always_log_errors: false` |
| `slow_threshold` | `*time.Duration` | `500ms` | `slow_threshold: 0s` |
| `sample_rate` | `float64` | `0.1` | `sample_rate: 1`，`Validate` 拒绝大于 1 |

判定顺序命中即定：排除路径或前缀就永不记录；`always_log_errors` 且 `status >= 400` 记录；耗时达到 `slow_threshold` 记录；`0 < sample_rate < 1` 按比例随机；否则记录。错误与慢请求都排在采样之前，采样吃不掉真正该看的请求。

三类字段判定「未配置」的方式各不相同，都是为了让「显式关闭」可表达：`excluded_paths` 判 `nil`，写成 `excluded_paths:` 不给值是 null，照样填回默认清单，只有显式 `[]` 才算退出；`always_log_errors` 与 `slow_threshold` 是指针，判 `nil`，`false` 与 `0s` 是显式关闭；`sample_rate` 判 `0`，所以显式全量必须写 `1`。

关掉慢请求旁路要写 `slow_threshold: 0s` 这种带单位的字符串，裸 `0` 过不了 `time.Duration` 的 yaml 解码（以 Izumo 修订后提交为准）。

慢请求旁路需要计时。`slow_threshold > 0` 时 `NewHertzServerV2` 会在 accesslog 之前自动注册一个只记开始时间的极薄中间件，因为上游 accesslog 自己的计时不对条件函数开放。绕开 `NewHertzServerV2` 自己拼中间件链的服务拿不到起始时间，耗时按 0 算，慢旁路静默失效——只会漏记，不会放大日志量。计时中间件插在 accesslog 之前，`OPTIONS` 的处理和其余中间件顺序都不变。

### 其他降级

- cron：robfig 每轮调度的 `wake`、`run`、`schedule`、`added`、`removed`、`start` 六条消息由 `Info` 降为 `Debug`。业务自己经 `cron.Logger` 打的消息和 `Error` 一路不变。
- Kafka：`Logger` 槽位降为 `Debug`，`ErrorLogger` 槽位用新构造器保持 `Error`，见上面的代码 API。
- GORM：`Options.Debug` 补上显式 `yaml:"debug"` tag，绑定行为不变。

### 升级时的行为变化

逐条确认。前三条改变运行时行为，第四条会直接编译失败：

1. 没写 `access_log` 配置块的服务自动进入上表的治理档，access log 量显著下降。`sample_rate: 0` 的含义也变了：旧版本表示不采样、记录全部，新版本表示未配置、落回 `0.1`。要保留「记录全部」必须显式写 `sample_rate: 1`，要保留「不排除探针」必须显式写 `excluded_paths: []`。升级前逐个仓库检查是否有依赖旧含义的配置。
2. OTel 出站多了一道 `info` 下限。此前把本地级别调到 `debug` 会连带出站 `DEBUG`，现在还要显式 `OTEL_LOG_MIN_SEVERITY=debug`。依赖出站 `DEBUG` 排障的流程要改。
3. cron 心跳与 kafka 客户端诊断日志降为 `Debug`。用 `wake`、`run` 做存活判断的告警要改看业务日志或指标。把原来那个适配器接在 kafka-go `ErrorLogger` 槽位上的服务，错误诊断会掉进 `Debug`，必须切到 `mq.NewKafkaErrorLoggerAdapterWithContext`。
4. `AccessLogConfig.AlwaysLogErrors` 由 `bool` 变成 `*bool`，`SlowThreshold` 是 `*time.Duration`。在代码里给这两个字段赋值的服务会编译失败，改用 `util.Ptr(true)`（`github.com/jihuanshe/Izumo/pkg/util`）。YAML 键不变，只写配置的服务不受影响。
5. `LOG_FILENAME` 从被忽略变成生效。升级前检查部署环境有没有残留的 `LOG_FILENAME`：它现在会把输出切成 stdout 加文件，路径不可写会直接启动失败。

## 已知缺陷与刻意取舍

这些事实影响判断，本轮不要求修复：

- access log 中间件刻意排在 CORS 之前（`pkg/httpserver/hertz.go:80` 的注释），好让被 CORS 短路的请求也留痕，代价是 `OPTIONS` 预检也会被记录。要静音就自己加排除路径或前缀，不要改中间件顺序。
- access log 写出的 `trace_id` 与 `span_id` 是普通字段，不是 LogRecord 的原生 `TraceId`，SigNoz 里点不进 trace。
- Redis 客户端没有 OTel hook，既没有 span 也没有慢查询日志。
- Kitex 本身没有 per-call 日志。但 `kitex-contrib/obs-opentelemetry` 的 `tracing/middleware.go:69` 在 suite 配置错误时，每次调用发一条 `Warn "TraceCarrier not found in context"`。这是 severity 门槛拦不住的 `Warn` 风暴，出现时先修 suite 装配。

## Collector 现状

Izumo 自带的样例配置 `pkg/opentelemetry/collector/otel-collector-config.yaml` 的 logs 管线：

```text
logs/in（:165）: otlp → memory_limiter → routing/logs
logs/signoz（:171）: routing/logs → batch → signoz
```

没有 `filter` processor，`tail_sampling` 只作用于 traces。现网真正生效的 Collector 配置不在本仓库，三个区域同样没有任何过滤，见 [Collector 兜底](collector-backstop.md)。服务发出多少日志，SigNoz 就收多少。

## 不可信的现有文档

下列说法与代码不符，不要据此判断：

| 出处 | 说法 | 事实 |
| --- | --- | --- |
| `tcg-backend-doc` `infrastructure.md:300`、`devops.md:203`、`SKILL.md:267` | `WithEnableLogs` 默认开 | 默认关（`options.go:160`） |
| Izumo `README.md:74` | 从 env 读 `LOG_LEVEL` / `LOG_FILENAME` | 已发布版本没有实现这两个 env，hygiene 变更才补上；对 pin 住旧版本的仓库仍然是错的 |
| tcg-base `configs/nacos/tcg-base-file-config.yaml:33-34` | 级别与采样走部署侧环境变量 | 该仓 pin 住的 Izumo 版本没有对应 env |

`tcg-backend-doc/skills/jhs-go-scaffold/references/business.md:1172` 的探针模板会在 `/ping` 里打 `Info`。新服务按本 Skill 生成探针，并同步修正该模板。
