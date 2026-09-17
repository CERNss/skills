# 验证方法

量改造前后的日志量，或核对某个服务的日志构成时用本文。全部是只读查询。

SigNoz 地址由用户提供，当前生产实例是 `https://signoz.apps.tongdiaotech.com`。API key 从用户或密钥库取，用 `SIGNOZ-API-KEY` 请求头传，禁止写进仓库、脚本或本 Skill。

## 三个必查口径

按 `service.name` 分组计数，取 24 小时窗口，改造前后各一次：

```bash
curl -sS -X POST "$SIGNOZ/api/v5/query_range" \
    -H "SIGNOZ-API-KEY: $SIGNOZ_API_KEY" \
    -H 'Content-Type: application/json' \
    -d '{
        "start": 1756000000000,
        "end": 1756086400000,
        "requestType": "scalar",
        "compositeQuery": {
            "queries": [{
                "type": "builder_query",
                "spec": {
                    "name": "A",
                    "signal": "logs",
                    "aggregations": [{"expression": "count()"}],
                    "groupBy": [{"name": "service.name"}]
                }
            }]
        }
    }'
```

字段名随 SigNoz 版本变化，发请求前对当前实例核对一次。把 `groupBy` 换成 `severity_text` 得到第二个口径：`info` / `warn` / `error` 的分布。第三个口径是单个服务的原始样本，用于判断日志构成。

## 不要用 body 做文本过滤

当前构建上对 logs 的 `body` 用 `CONTAINS`、`LIKE` 或 `REGEXP` 会返回 HTTP 500；实测一次 `CONTAINS` 查询把 query-service 打挂约 3 分钟。

替代做法：取一个 30 秒窗口的原始记录（`limit` 约 2000），在本地解析 method、path、status 和 body 前缀，再按比例外推。访问日志靠 `attributes["type"] == "http.HertzHttpServer"` 与业务日志区分。

## 验收目标

| 口径 | 目标 |
| --- | --- |
| 空闲 pod 的 `INFO` 速率 | 0 条每分钟 |
| 探针类路径的日志计数 | 0 |
| HTTP 服务的 2xx 访问日志条数 | 不超过 `sample_rate` 乘以请求数 |
| 改造前后 24 小时同口径计数 | 降幅与 PR 里的预期一致 |

## 当前基线

2026-09-02 10:45 UTC 起前推 24 小时，全量 85615399 条。留作后续对比的基准：

| 口径 | 数值 |
| --- | --- |
| `info` / `warn` / `error` | 92.4% / 5.9% / 1.4% |
| `debug` 与 `trace` | 0.00% |
| 2xx 访问日志（估算） | 约 6300 万条，约 74% |
| 探针类路径 | 3.1%，约 266 万条；其中 `/ping` 占 1.0% |
| 前五服务中访问日志占比 | 88.4% |

服务分布见 [按仓库的整改清单](remediation-by-repo.md)。

## stdout 与 SigNoz 的关系

SigNoz 侧没有 filelog receiver，Kubernetes 容器 stdout 不会进 SigNoz。stdout 由 Grafana Alloy DaemonSet 全量采进 Loki。因此：

- 只写 stdout 而不接 OTLP 的服务在 SigNoz 里完全看不到，但在 Loki 里能查。
- 接了 OTLP 的服务，每条日志被存两份：ClickHouse 一份，Loki 一份。这是 OTel 侧必须精选而不是照搬 stdout 的直接原因。
