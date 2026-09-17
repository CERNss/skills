# 各技术栈落地

出站边界对所有语言一致。本文只写各栈把边界落到代码或配置上的具体位置。Go + Izumo 是主栈，其余按需读。

服务侧改不完时的兜底见 [Collector 兜底](collector-backstop.md)。

## Go + Izumo + Hertz

配置见 [配置基线](config-baseline.md)。三条代码侧要求：

- 探针从裸 `net/http` mux 或 `launcher.AdminHertzModule` 提供，不走业务端口的中间件链。
- 禁止在 Izumo access log 之上再注册手写访问日志中间件。
- 循环内确实要在本地看的记录加 `log.Loop()` 标记（含 hygiene 变更的 Izumo），留在 stdout 不出站。

## Go + Izumo worker 与 consumer

worker 没有 access log，全部量来自业务日志。核心是「做了事才记」：

```go
if processed > 0 {
    log.Info(ctx, "batch processed",
        zap.Int("processed", processed),
        zap.Int("failed", failed),
        zap.Int64("elapsed_ms", elapsed.Milliseconds()))
}
```

模型：tcg-card-binder `order_event_inbox_worker.go:121`。消费循环里每条消息的进入与跳过记 `Debug`，模型：tcg-crawler-preprocess。定时器上报数量用 metric 不用日志，模型：tcg-idlinker `consumer/stats.go`。

消费失败重试必须有退避。`for` 循环里 `continue` 且不退避，会在 broker 故障时把错误日志打成风暴。

kafka-go 的 `Logger` 与 `ErrorLogger` 两个槽位要分别接不同的 Izumo 适配器，级别与构造器名见 [Izumo 机制](izumo-mechanics.md)。

## Go 裸 net/http + slog

两个可直接抄的现网实现：

- rotom `internal/authserver/http.go:81`：只记 `status >= 400`。手写访问日志的默认形态必须是这样。
- auto-reviewer `internal/httpapi/auth.go:309`：访问日志之前先对 `/healthz`、`/readyz` 提前返回。

`slog` 不带 `ctx` 时没有 `trace_id`。用 `slog.InfoContext(ctx, ...)`，并接 OTel handler。

## Go + GORM 自建 logger

不用 Izumo `pkg/database` 而自己 `gorm.Open` 时，必须显式给 `Logger`：

```go
gormLogger := zapgorm2.New(zapLogger)
gormLogger.IgnoreRecordNotFoundError = true
gormLogger.SetAsDefault()
```

GORM 默认 logger 的 `IgnoreRecordNotFoundError` 是 `false`、`Colorful` 是 `true`。业务里正常的「查不到」会变成带完整 SQL 和 ANSI 转义序列的 `ERROR`，一个请求可能产生上百条。riftdeck_backend `internal/source/postgres.go:23` 是这个反例。

自己 `gorm.Open` 而不设 `Logger` 时，配置里的 `debug` 键是死配置，既不出 SQL 日志也不出 SQL span。

## Python FastAPI + uvicorn

- uvicorn 访问日志用 `--no-access-log` 关掉，或在 logging 配置里给 `uvicorn.access` 加过滤器丢弃探针路径。
- 埋点时必须传排除路径。ai-lab `apps/tcgen/entrypoint.py:24` 的 `EXCLUDED_URLS = "/health,/docs,/openapi.json"` 是现网最完整的一份，直接抄。
- 禁止 `capture_headers=True`。禁止把响应体写进 span attribute。
- 控制台镜像输出（例如 `configure_logfire(is_console=True)`）在生产关掉，它会把每条日志按 `DEBUG` 再打一遍 stdout。
- `APScheduler`、`urllib3`、`botocore` 等库 logger 设为 `WARNING`。

## Python 标准 logging 与 loguru

接 OTel 时给 handler 设级别下限，不要把 root logger 挂到 `INFO` 再全量转发：

```python
handler = LoggingHandler(level=logging.INFO)
logging.getLogger("crawler").addHandler(handler)
```

挂在 root 上会把所有第三方库的 `INFO` 一并出站。ai-lab `apps/spider/common/observability.py:78` 是这个反例。loguru 同理：`logger.add(sink, level="INFO")` 只加在业务 sink 上。

`log.info(data)` 这种把整个抓取结果当消息打的写法一律改成 ID 加计数。

## Node 与 Express

```js
pinoHttp({
    autoLogging: {
        ignore: (req) => ["/health", "/healthz", "/readyz", "/ping", "/metrics"].includes(req.url),
    },
});
```

OTel log transport 单独设最低级别，与本地级别解耦。手写 `node:http` 服务同样要有 skip list；tcg-kefu-backend `internal/httpapi/router.go:87` 把整个 mux 包起来且没有 skip list，是反例。

## Convex

Convex function 里的 `console.*` 由 sidecar 转成 OTLP，按条计费。tcg-convex `docs/company-rpc.md` 是公司目前唯一一份成文日志约定，Convex 侧照它执行。

- 每次 RPC 一条 `console.info` 属于 per-call 成功日志，禁止。
- 网关传来的 trace id 必须透传到日志，不要丢弃。
- 轮询式实现（每 500ms 一次）先改设计，再谈日志。

sidecar 侧默认不上报「静默成功」的执行，见 convex-otel-sidecar `exporter.go:100`。

## Deno 2

- systemd unit 里的 `--log-driver none` 会把日志直接丢弃，先移除。
- 内置 OTel 用 `OTEL_DENO=1` 打开，不要自己写导出器。
- `setInterval` 定期上报的对象改成 metric，不要每分钟打一条大对象。

## Bun 或 Node CLI 任务

systemd timer 拉起的一次性任务，stdout 归 journald，不进 OTel。要接 OTel 时先把 KB 级 JSON dump 改成摘要，或者保持 stdout 不接采集。

## nginx

探针 location 单独关掉访问日志：

```nginx
location = /healthz {
    access_log off;
    return 200;
}
```

tcg-identity-platform 目前用默认配置记录每个 2xx 和探针请求。

## PHP 5.6 等历史运行时

运行时不支持 OpenTelemetry 时，本 Skill 的出站边界不适用，但级别语义仍然适用：

- 生产的 `APP_LOG_LEVEL` 不能是 `debug`。
- 每次加锁与解锁记 `Log::info` 这类热路径日志同样要降级。wxygo-svr `RedisDistributedLock.php:55,151` 是反例。
- 在 PR 里按 [出站标准](standard.md) 的豁免条款写明原因与回迁条件。
