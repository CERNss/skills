# Collector 兜底

Collector 侧丢弃是兜底手段，不是第一手段。噪音的正确处理是服务不产生它。只有在服务方短期改不完、且量已经在计费时才用本文。

Collector 丢掉的日志不可恢复，且服务方看不到自己被丢了什么。加规则时必须同步通知服务 owner，并在规则里写明预期何时撤回。

## 配置在哪里

现网生效的 Collector 配置不在 Izumo 仓库，也不在 tcg-infra 或 tcg-gitops（那两个是 Go controller）。它在 `tongdiao-infra/cern-gitops`：SigNoz Helm chart 0.110.0 经 kustomize `helmCharts` 部署，路径 `signoz/{cn-beijing,ap-tokyo,cn-hongkong}/kustomization.yaml`，Collector 配置来自 `otelCollector.config`，原样渲染成 ConfigMap。

三个区域当前的 logs 管线一致：

```text
receivers  [otlp, httplogreceiver/heroku, httplogreceiver/json]
processors [batch]
exporters  [clickhouselogsexporter, metadataexporter, signozmeter]
```

没有 `filter`，没有 `transform`。SigNoz UI 侧的 log pipelines 也是空的（`GET /api/v1/logs/pipelines/latest`）。

## 改之前必须知道的两件事

`cn-beijing/values.yaml:1-18` 与 `cn-hongkong/values.yaml:9-14` 把 `config.processors.batch` 和 `exporters.clickhouselogsexporter` 挂在 `clickhouse:` 下面而不是 `otelCollector:` 下面，这两段是死配置，从未生效。只有 `ap-tokyo/values.yaml:80-100` 真正覆盖了 Collector。加规则的同一个 PR 里修掉这个错位。

Helm 合并 map 但整体替换 list。新增一个 processor 时必须把 `service.pipelines.logs` 的 `receivers`、`processors`、`exporters` 三行全部重写一遍，否则会静默丢掉 heroku 与 json receiver 以及 metadata 与 meter exporter。

## 规则草稿

用之前先确认 `signoz-otel-collector` v0.144.x 编进了 `filterprocessor`。没编进去就退回 SigNoz UI 的 log pipeline drop rule，但那条路径不在 GitOps 管理范围内，要单独记录。

```yaml
otelCollector:
  config:
    processors:
      filter/drop_noise:
        error_mode: ignore
        logs:
          log_record:
            - 'attributes["type"] == "http.HertzHttpServer" and IsMatch(body, "^[0-9]{3} - +[0-9.]+[a-zµ]+ +[A-Z]+ +/(ping|healthz?|readyz|livez|metrics)([/?]|$)")'
            - 'attributes["type"] == "http.HertzHttpServer" and IsMatch(body, "\\| [A-Z]+ +/(ping|healthz?|readyz|livez|metrics)([/?]| \\|)")'
            - 'body == "ping"'
            - 'severity_number != SEVERITY_NUMBER_UNSPECIFIED and severity_number < SEVERITY_NUMBER_INFO'
    service:
      pipelines:
        logs:
          receivers: [otlp, httplogreceiver/heroku, httplogreceiver/json]
          processors: [filter/drop_noise, batch]
          exporters: [clickhouselogsexporter, metadataexporter, signozmeter]
```

两条 `IsMatch` 分别对应 Izumo 的 access log 格式（`200 - 66.5ms GET /path`）和网关的格式（`hh:mm:ss | 200 | 61ms | ip | uid=- | GET /path | ua="…"`）。最后一条 severity 规则今天丢不到东西，现网 `DEBUG` 与 `TRACE` 占比 0.00%，它防的是将来有人打开 `debug`。

## 不要在 Collector 做的事

- 不要按 `service.name` 整体丢弃。那会把该服务的 `ERROR` 一起丢掉。
- 不要用 Collector 替代服务侧采样。采样要保留统计代表性，`filter` 是无条件丢弃。
- 不要把规则当长期方案。每条规则都要有对应的服务侧整改任务。
