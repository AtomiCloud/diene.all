# Curated dashboards

This directory starts empty. Add dashboard JSON only when a Gate 4 decision in
`../SIGNALS.md` approves custom/domain panels that the generic LPSM dashboard
does not already provide.

- `overview.json` is the first curated dashboard and the target for alert panel
  links.
- Additional files are single-purpose deep dives linked from `overview.json`.
- Each file carries a deterministic `<platform>-<service>-<purpose>` UID.
- Every dashboard is linted, rendered in the sandbox, and visually inspected
  before merge.

The service's primordial chart emits one `GrafanaDashboard` per JSON file. See
the [dashboard standard](../../docs/standards/grafana-dashboards/index.md) and
[rendering convention](../../docs/standards/observability/primordial-chart.md).
