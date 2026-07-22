# Dashboard Profiles

Use this file to decide how the same telemetry model becomes two outputs.

## Shared Rule

Generate `full` and `lite` from the same telemetry model.
Do not let them drift into separate metric contracts.

## Full Profile

Intent:
- complete coverage
- service health and service status
- dependency visibility
- error triage
- deep drilldown entry points

### Full must include

1. Core service health:
- throughput
- error rate
- latency percentiles

2. Operational splits:
- top-level operation or route split
- result or status split
- service split when multiple services exist

3. Dependency coverage:
- queue, db, cache, external, or scheduler panels if present in telemetry model

4. Triage coverage:
- top failing dimensions
- top slow dimensions
- recent failure summary or equivalent

5. Drilldown coverage:
- traces, logs, or service-map entry if available

### Full row guidance

Prefer this order:
1. `Service Health`
2. `Errors / Exceptions`
3. `API / Request Flows`
4. `Workers / Async / Queue`
5. `Dependencies`
6. `Persistence / Cache / Database`
7. `Trace / Log Drilldown`

Rows may be omitted only when the telemetry model has no evidence for that domain.

## Lite Profile

Intent:
- one-page oncall inspection
- quickest answer to "is the system healthy right now?"
- immediate drilldown entry to traces or logs

### Lite must include

1. top summary values:
- throughput
- error rate
- p95 or p99 latency

2. highest-risk dependency summary:
- queue retry or dlq
- external dependency health
- db or cache health if critical

3. high-value trend charts:
- request or operation latency trend
- consumer or worker latency trend when async exists
- one dependency trend only if it materially affects oncall response

4. drilldown entry:
- failed traces
- slow traces
- correlated logs
- top failing operation summary

### Lite composition rules

1. Keep lite to one page.
2. Keep roughly 8 to 12 widgets.
3. Every widget must justify its presence for detection or triage.
4. Prefer values and a small number of trend charts over many split charts.
5. Avoid repeating the same metric across multiple lite widgets unless the second panel adds a different action path.
6. If multiple dependencies exist, choose only the most operationally risky ones.

### Lite row guidance

The first row title must be:
- `一屏总览（值班核心健康信号）`

A sensible default layout is:
1. KPI values row
2. latency and dependency trend row
3. exception or error summary row
4. drilldown entry row
