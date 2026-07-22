# Fact Extraction Patterns (OTel Dashboard)

Use these repeatable extraction patterns to build a traceable fact inventory.

## 1. Fast file discovery

```bash
rg --files <repo_root>
```

## 2. Metric instrumentation search

```bash
rg -n "(Int64Counter|Float64Counter|Int64Histogram|Float64Histogram|ObservableGauge|Meter\()" <repo_root>
```

## 3. Tracer/span readiness search

```bash
rg -n "(Tracer\(|Start\(|span\.|trace_id|span_id|otel|opentelemetry)" <repo_root>
```

## 4. Service/env identity search

```bash
rg -n "(service\.name|OTEL_SERVICE_NAME|deployment\.environment|OTEL_RESOURCE_ATTRIBUTES)" <repo_root>
```

## 5. Dependency and async flow search

```bash
rg -n "(redis|mysql|postgres|kafka|rabbit|sqs|queue|worker|cron|scheduler|batch|rpc|http client)" <repo_root>
```

## 6. Existing dashboard metric key extraction

```bash
jq -r '..|objects|select(has("aggregateAttribute"))|.aggregateAttribute.key' <dashboard.json> | sort -u
```

## 7. Existing dashboard label extraction

```bash
jq -r '..|objects|select(has("groupBy"))|.groupBy[]?' <dashboard.json> | sort -u
```

## 8. Layout/widget mapping validation

```bash
comm -3 \
  <(jq -r '.layout[].i' <dashboard.json> | sort) \
  <(jq -r '.widgets[].id' <dashboard.json> | sort)
```

## 9. Fact table format

```markdown
| fact_id | fact_type | fact | evidence | source_kind | status | notes |
| --- | --- | --- | --- | --- | --- | --- |
| F-001 | service | service.name=inventory-api | cmd/server/main.go:42 | code | confirmed |  |
| F-014 | metric | inventory_request_total | internal/telemetry/http.go:57 | code | confirmed | counter |
| F-025 | label | status_code | internal/telemetry/http.go:63 | code | confirmed | low-cardinality |
| F-090 | dependency | redis cache | docs/architecture.md:28 | doc | 待确认 | code evidence missing |
```

## 10. Unknown handling

1. If a requested relation is not provable, mark it as `待确认`.
2. Keep `待确认` rows separate from confirmed rows in facts mapping output.
3. Do not infer fallback behavior not present in evidence.
