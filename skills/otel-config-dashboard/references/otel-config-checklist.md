# OTel Config Checklist

Use this checklist after generating `otel-collector-config.yaml`.

## Pipeline Integrity

1. Ensure each declared signal (`traces`, `metrics`, `logs`) has a complete pipeline.
2. Ensure every pipeline has at least one receiver and one exporter.
3. Ensure processor order is safe: `memory_limiter` before `batch` in most cases.
4. Ensure extensions used by `service.extensions` are defined.

## Runtime Alignment

1. Ensure `service.name` derives from runtime env (`OTEL_SERVICE_NAME` or equivalent).
2. Ensure environment attributes are explicit (`deployment.environment`, `service.namespace`, region keys).
3. Ensure endpoint/protocol settings match deployment target (OTLP gRPC vs OTLP HTTP).
4. Ensure sensitive values are injected via env, not hardcoded in YAML.

## Data Shape Alignment

1. Ensure exported metrics include names defined in the metrics contract.
2. Ensure label keys expected by dashboard queries can be produced by instrumentation.
3. Ensure no processor removes labels required by dashboard filters/grouping.
4. Ensure no transform introduces unstable high-cardinality labels.

## Evidence Traceability

1. Ensure each non-default receiver/processor/exporter has at least one evidence reference (`path:line` or canonical doc path).
2. Ensure checklist action items map to concrete code or deployment paths.
3. Ensure any unverifiable pipeline assumption is marked `待确认` and not presented as implemented.

## Output Readiness

1. Ensure YAML syntax is valid.
2. Ensure placeholder env keys are documented next to output.
3. Ensure config comments or README notes describe non-default processors/exporters.
