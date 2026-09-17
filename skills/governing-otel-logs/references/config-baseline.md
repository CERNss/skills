# 配置基线

给一个 Go + Izumo 服务补配置时按本文抄。配置块的绑定路径以该服务 `httpserver.Options` 的实际绑定为准，通常是 `http.middleware.access_log`。

## access_log

```yaml
access_log:
  excluded_paths: ["/ping", "/health", "/healthz", "/readyz", "/livez", "/metrics"]
  sample_rate: 0.1
  always_log_errors: true
  slow_threshold: 500ms   # 仅含 hygiene 变更的 Izumo 支持
```

- `excluded_paths` 是精确匹配。服务如果把探针挂在 `/api/v8/pokemon/healthz` 这类带前缀的别名上，必须把别名逐条列出；含 hygiene 变更的 Izumo 可以改用 `excluded_prefixes`。
- `always_log_errors: true` 让 4xx 与 5xx 不受采样影响，始终记录；`slow_threshold` 给慢请求同一条旁路。
- 旧版本没有 `slow_threshold` 与 `excluded_prefixes`，写了不生效；是否报错取决于服务自己的 yaml 解码严格度。`slow_threshold` 是 duration，一律写带单位的字符串。
- 这四项与含 hygiene 变更的 Izumo 的默认档位一致。升级后仍然显式写出来：一份配置在新旧版本上行为相同，读配置的人也不必去查框架默认值。零值与显式退出的语义差异见 [Izumo 机制](izumo-mechanics.md)。

## 采样档位

按服务自身的请求量选，不按重要性选：

| 每日请求量 | `sample_rate` |
| --- | --- |
| 超过 100 万 | 0.01 |
| 10 万到 100 万 | 0.05 |
| 低于 10 万 | 0.1 |
| admin、内部工具 | 1.0 |

被 `tcg-gateway` 代理的后端在上表基础上再降一档到 `0.01`，成功请求由边缘保留。错误和慢请求不受采样影响。

## 环境变量

写在 gitops 的 env：

```text
LOG_LEVEL=info
OTEL_LOG_MIN_SEVERITY=info
OTEL_EXPORTER_OTLP_PROTOCOL=grpc
```

`OTEL_LOG_MIN_SEVERITY` 允许对噪音大、短期改不完的服务临时设成 `warn`。这是闸门不是终态，必须在 PR 里写明何时撤回。`LOG_LEVEL` 与 `OTEL_LOG_MIN_SEVERITY` 只在含 hygiene 变更的 Izumo 生效。

不改代码临时压某个环境的访问日志量时用 `IZUMO_ACCESS_LOG_SAMPLE_RATE` 与 `IZUMO_ACCESS_LOG_EXCLUDED_PATHS`，要彻底关掉日志导出时用 `OTEL_LOGS_EXPORTER=none`。这三个变量的取值语义、优先级和踩坑点见 [Izumo 机制](izumo-mechanics.md)。

## 数据库

staging 与 prod 必须是 `debug: false`。

```yaml
database:
  debug: false
  enable_tracing: true
```

要看 SQL 就看 span，不看 SQL 日志。`debug: true` 会把每条 SQL 变成一条出站 `Info`。

## 可复制的现网样例

- `tcg-pokemon` `configs/nacos/tcg-pokemon.yaml:16-19`：`sample_rate: 0.1` + `always_log_errors: true` + `excluded_paths: ["/healthz", "/readyz"]`，配合 prod `debug: false` 与 `enable_tracing: true`。这是当前最完整的一份，可直接作为模板。它唯一的缺口是没有排除 `/api/v8/pokemon/healthz` 与 `readyz` 两个别名。
- `tcg-gateway` `configs/config.tmpl.yaml`：采样 0.1、排除 `/healthz` 与 `/ping`，并用代码级 tag 写出 `auth_user_id`。边缘服务照这份抄。
- `tcg-inventory-sync` `internal/app/webhook/router.go:31`：在代码里设 `ExcludedPaths`。没有配置中心的入口用这种写法。
