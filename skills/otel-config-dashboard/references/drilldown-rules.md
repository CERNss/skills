# Drilldown Rules

Use this file to decide how dashboards expose root-cause paths beyond metrics.

## Goal

Dashboards should not stop at "something is wrong".
They should point to the next place a user should inspect.

## Signal Readiness Checks

Before adding drilldown panels, determine which of these are truly available:
- traces available
- logs available
- logs correlated with traces by `trace_id` or `span_id`
- service map available

If a signal is unavailable, do not pretend it exists.
Record the limitation in analysis markdown.

## Preferred Drilldown Order

1. traces
2. correlated logs
3. service map
4. metric-only fallback summaries

## When traces are available

Prefer drilldown panels that help users enter trace analysis quickly:
- recent failed traces
- recent slow traces
- top failing operations with trace-aware filters
- top slow dependencies

Use low-cardinality fields only for dashboard filters and grouping.
Do not expose `trace_id` as a dashboard variable.

## When correlated logs are available

Add high-value log entry points such as:
- recent error logs for selected service or operation
- exception-type summaries
- logs related to failed traces

If logs are present but correlation is not configured:
- do not imply trace-linked log drilldown
- state that correlation must be added for full metrics-to-logs-to-traces navigation

## When service map is available

Use service map as a dependency navigation aid.
It is especially useful when the telemetry model shows multiple services or downstream dependencies.

## Metric-only fallback

If traces and logs are unavailable, the dashboard must still provide next-step clues:
- top failing operation
- top slow operation
- top failing dependency
- queue retry or dlq hotspot
- scheduler failure split

This is a fallback, not the preferred end state.

## Lite-specific rules

Lite must keep only one or two drilldown entry panels.
Choose the highest-value entry points, usually:
- failed traces
- slow traces
or, if traces are unavailable:
- top failing operation
- top slow dependency

## Full-specific rules

Full can include multiple drilldown entry points when they materially shorten time to diagnosis.
Do not add decorative trace or log panels that duplicate the same signal without improving triage.
