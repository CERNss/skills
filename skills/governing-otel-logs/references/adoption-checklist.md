# 采用清单

在一个服务仓上执行。命令按目标仓的实际目录调整；给出的模式用于定位候选，判定仍由你逐条做。

先读 [按仓库的整改清单](remediation-by-repo.md) 里该仓已经确认的问题，再开始扫描。

## 1. 确认导出状态与 Izumo 版本

```bash
rg -n 'WithEnableLogs|OTelProvider' --glob '*.go'
rg -n 'jihuanshe/Izumo' go.mod
```

`WithEnableLogs(true)` 不存在时，这个服务的日志根本没到 SigNoz。此时禁止先打开开关：先做完第 3 步到第 8 步，再在同一个 PR 或紧随其后的 PR 里打开。

要使用 `OTEL_LOG_MIN_SEVERITY`、`log.Loop()`、`excluded_prefixes` 或 `slow_threshold`，先把 Izumo 升到含 `feat/otel-log-hygiene` 的下一个 beta。升级会改变 `sample_rate: 0` 的含义、把 `AlwaysLogErrors` 变成 `*bool`（代码里给它赋值的服务会编译失败），并把 cron 心跳与 kafka 客户端日志降为 `Debug`。逐条对照 [Izumo 机制](izumo-mechanics.md) 的升级清单，并确认 kafka 的 `ErrorLogger` 槽位：

```bash
rg -n 'AlwaysLogErrors|SlowThreshold|ErrorLogger' --glob '*.go'
```

同时检查该服务在 gitops 里有没有残留的 `LOG_FILENAME`：升级前它被忽略，升级后会把输出切成 stdout 加文件，路径不可写就直接启动失败。

## 2. 补 access_log 配置块

```bash
rg -n 'access_log' configs/
```

按 [配置基线](config-baseline.md) 给每个 HTTP 入口补齐。配置模板和 nacos 模板都要改：仓库里的 `configs/config.tmpl.yaml` 只影响新环境，已部署环境读的是 nacos。列出需要重新发布的 nacos 配置 ID，写进 PR。

同时确认没有第二份手写 access log：

```bash
rg -ni 'access.?log' --glob '*.go'
```

## 3. 清理探针 handler

```bash
rg -n --glob '*.go' -A6 '"/(ping|health|healthz|readyz|livez)"' | rg -n 'log\.|Info|Println'
```

探针 handler 内部不打任何日志。worker 与 consumer 侧的探针用裸 `net/http` mux 或 `launcher.AdminHertzModule`，不经过 access log 链路。

## 4. 扫热路径

handler、consumer、循环、轮询、cron 四类路径逐个看。

```bash
ast-grep run -p 'for $$$ { $$$ log.Info($$$) $$$ }' -l go
rg -n 'log\.Info\(ctx, "(.*)(tick|scan|poll|轮询|扫描|开始执行|执行完成|队列为空)' --glob '*.go'
rg -n 'zap\.Any\(' --glob '*.go'
rg -ni 'formData|request_body|response_body|requestBody|responseBody|Authorization|headers' --glob '*.go'
```

处理方式：

- per-item、per-message、per-row 的 `Info` 降为 `Debug`，或聚合成批次摘要。
- tick、dispatch、poll 的日志加 `count > 0` 之类的工作量门控，或改成 metric。
- 循环内确实要在本地看的 `Warn` 与 `Info` 加 `log.Loop()` 标记，留在 stdout 不出站。
- 单请求内的 `start` / `step` / `end` / `result` 轨迹日志直接删除，链路由 span 表达。

## 5. 关掉 SQL 日志

```bash
rg -n 'debug:\s*true' configs/
```

staging 与 prod 一律 `debug: false`，需要看 SQL 时打开 `enable_tracing`。已部署的 nacos 配置同样要改。

## 6. 补 ctx

```bash
rg -n '\.(Debug|Info|Warn|Error)\("' --glob '*.go'
ast-grep run -p 'zap.L().$M($$$)' -l go
```

第一条命令命中的是首参为字符串字面量的调用，即没有传 `ctx`，日志里不会有 `trace_id`。改成 `log.X(ctx, msg, fields...)`。

## 7. 清敏感内容

请求与响应 body、header 集合、Elasticsearch query DSL、SQL 原文、邮箱、用户名一律不进日志。需要定位问题时记 ID，不记内容。

## 8. 验证

本地起服务，连打十次探针，stdout 必须不出现访问日志：

```bash
for _ in $(seq 10); do curl -s -o /dev/null http://127.0.0.1:8080/ping; done
```

线上按 [验证方法](verification.md) 取改造前后各 24 小时的计数。

## 9. 写 PR

PR body 至少包含三段：

```text
## 改了什么
- access_log：补 excluded_paths / sample_rate / always_log_errors
- 探针：移除 N 处 handler 内日志
- 热路径：M 条 per-item Info 降级或删除
- database.debug：staging / prod 置 false

## 预期日志量
- 改造前 24h：<service.name> = X 条
- 预期降幅：约 Y%，主要来自 <哪一项>
- 上线后 24h 复核结论：<留待补充>

## 需要发布的 nacos 配置
- <config-id>（<env>）
```
