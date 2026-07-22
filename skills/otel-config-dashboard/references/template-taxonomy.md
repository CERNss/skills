# Template Taxonomy

Use this file to map the telemetry model to dashboard packs.
Treat official SigNoz templates as design families, not as copy-paste outputs.

## Core Principle

Build dashboards by composing packs.
Do not start by copying a single large template and renaming metrics.

## Base Packs

### 1. Base health pack
Use for every service dashboard.
Typical content:
- throughput or request rate
- error rate
- p50 or avg latency
- p95 or p99 latency
- top operations or top error dimensions
- service or environment variables

### 2. Error and triage pack
Use for every full dashboard.
Typical content:
- top failing operations
- top failing dependency or method
- error trend
- exception type or error result splits
- recent failures table or high-signal summary

### 3. Drilldown pack
Use whenever traces, logs, or service map are available.
Typical content:
- failed traces entry
- slow traces entry
- correlated logs entry
- service map entry or dependency summary

## Optional Domain Packs

### API pack
Use when the repo serves request or endpoint traffic.
Typical dimensions:
- route
- operation
- method
- result
- status code

### Worker or async pack
Use when background jobs, consumers, or schedulers exist.
Typical dimensions:
- topic
- queue
- task type
- batch outcome
- worker name

### Queue pack
Use when MQ, Kafka, RabbitMQ, SQS, or similar systems exist.
Typical content:
- publish rate
- consume rate
- retry rate
- dlq ratio
- backlog or lag when available

### Cache pack
Use when Redis or cache telemetry exists.
Typical content:
- hit rate
- miss rate
- hit ratio
- cache latency
- cache split by cache name when low cardinality

### Database pack
Use when db client spans or db metrics exist.
Typical content:
- db calls rate
- avg or p95 duration
- top slow queries or operation groups when normalized
- db error rate

### External dependency pack
Use when the service calls third-party or internal downstream APIs.
Typical content:
- external call rate
- external error rate
- external latency
- top failing downstreams

### Scheduler or batch pack
Use when periodic or long-running jobs exist.
Typical content:
- run outcome
- user or entity throughput
- batch size
- batch duration
- overdue or skipped work if instrumented

### Host or k8s pack
Use only if infra metrics exist.
Typical content:
- cpu
- memory
- restart count
- disk or network pressure
- pod or node health

### Frontend pack
Use when browser or user experience telemetry exists.
Typical content:
- core web vitals
- route latency
- frontend errors
- browser split or device split

### LLM pack
Use when LLM or agent telemetry exists.
Typical content:
- request count
- token usage
- latency
- provider error rate
- model split

## Pack Selection Rules

1. Always include base health, error and triage, and drilldown packs.
2. Add optional packs only when the telemetry model supports them.
3. Prefer fewer high-signal packs over many weak packs.
4. In lite mode, compress optional packs into only the most critical summary panels.
5. In full mode, expand packs only when they contribute to root-cause analysis.
6. Never add a pack purely because it appears in a public template gallery.
