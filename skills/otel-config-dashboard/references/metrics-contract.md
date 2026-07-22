# Metrics Contract

Build this contract before writing dashboard JSON or OTel config.
Treat it as the single source of truth.

## Required Columns

| field | required | description | example |
| --- | --- | --- | --- |
| `metric_name` | yes | Exact OTel metric key used in exporter and dashboard query | `http_server_duration_seconds` |
| `metric_type` | yes | OTel type | `counter`, `gauge`, `histogram` |
| `unit` | yes | Display and semantic unit | `s`, `ms`, `bytes`, `percent`, `none` |
| `allowed_labels` | yes | Labels allowed in dashboard `filters`, `groupBy`, and variables | `service_name, route, method, status_code` |
| `default_aggregation` | yes | Main aggregation used for value/graph panels | `rate`, `avg`, `p95` |
| `panel_intent` | yes | Preferred panel category | `value`, `graph`, `table`, `bar`, `pie`, `histogram` |
| `must_visualize` | yes | Whether metric must appear in at least one panel | `true`, `false` |
| `source_fact_ids` | yes | Fact row IDs proving this metric and label boundary | `F-021,F-022` |
| `evidence_paths` | yes | One or more `path:line` references | `internal/api/otel.go:88;docs/obs.md:41` |
| `status` | yes | `confirmed` or `待确认` | `confirmed` |
| `notes` | no | Constraints and exclusions | `Do not group by user_id` |

## Hard Rules

1. Do not create contract rows without evidence.
2. `source_fact_ids` and `evidence_paths` are mandatory for all rows.
3. `status=待确认` rows must not be used by default in dashboard queries.
4. Only labels in `allowed_labels` may appear in dashboard queries.
5. IDs and trace fields must not be used as high-cardinality dimensions.

## Mapping Rules

1. `counter` usually maps to `Sum` + `rate` or `increase`.
2. `gauge` usually maps to `Gauge` + `avg` or `latest`.
3. `histogram` usually maps to percentile operators (`p50`, `p90`, `p95`, `p99`).
4. Dashboard metric keys must map one-to-one with `metric_name`.
5. Dashboard labels must be a subset of `allowed_labels`.

## Markdown Template

```markdown
| metric_name | metric_type | unit | allowed_labels | default_aggregation | panel_intent | must_visualize | source_fact_ids | evidence_paths | status | notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| http_requests_total | counter | none | service_name,route,method,status_code | rate | graph | true | F-021,F-022 | internal/http/otel.go:51;docs/obs-metrics.md:12 | confirmed | Do not group by client_ip |
| http_request_duration_seconds | histogram | s | service_name,route,method,status_code | p95 | graph | true | F-023 | internal/http/otel.go:84 | confirmed | Keep route normalized |
| process_resident_memory_bytes | gauge | bytes | service_name,instance | avg | value | true | F-041 | internal/runtime/metrics.go:27 | confirmed |  |
```

## Validation Checklist

1. Every dashboard metric key exists in `metric_name`.
2. Every `must_visualize=true` metric appears in at least one panel.
3. Every dashboard `groupBy`, filter key, and variable key belongs to `allowed_labels`.
4. Every contract row has valid `source_fact_ids` and `evidence_paths`.
5. No `status=待确认` metric is used in default dashboard queries.
6. Panel units are compatible with metric `unit`.
