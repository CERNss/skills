# Fact Extraction Patterns

Use these repeatable extraction patterns to build evidence tables.

## 1. Fast File Discovery

```bash
rg --files <repo_root>
```

## 2. Metric Instrument Search

```bash
rg -n "(Int64Counter|Float64Histogram|Int64Histogram|Float64Counter)\(" <repo_root>
```

## 3. Service/Provider Entry Points

```bash
rg -n "service\.name|otel|provider|meter|tracer" <repo_root>
```

## 4. Dashboard Metric Key Extraction

```bash
jq -r '..|objects|select(has("aggregateAttribute"))|.aggregateAttribute.key' <dashboard.json> | sort -u
```

## 5. Layout/Widget Mapping Validation

```bash
comm -3 \
  <(jq -r '.layout[].i' <dashboard.json> | sort) \
  <(jq -r '.widgets[].id' <dashboard.json> | sort)
```

## 6. Evidence Table Format

| Fact Type | Fact | Evidence | Notes |
|---|---|---|---|
| Metric | `inventory.operation.total` | `internal/service/inventory.go:59` | Counter |
| Label | `status` | `backend-doc/...:line` | low-cardinality |
| Panel | `Worker Error Rate` | `dashboard.json:line` | formula |

## 7. Unknown Handling

1. If requested relation is not provable, mark `待确认`.
2. Never infer fallback behavior not present in facts.
3. Keep unknowns separate from confirmed fact table.
