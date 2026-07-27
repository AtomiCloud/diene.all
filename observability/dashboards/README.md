# Curated dashboards

The fleet-operator's generic reconcile + fleet-taxonomy dashboard (reconcile RED,
condition state, timestamp staleness, ledger/vendor failures, provisioning
duration, the webhook config-plane, and the observe-mode plan surface) ships today
as the chart's `dashboard.yaml`. This directory stays a scaffold — a Phase 4
curation boundary.

Add dashboard JSON here only when a Gate 4 decision in `../SIGNALS.md` approves
custom/domain panels that the generic LPSM dashboard and the in-chart dashboard do
not already provide.

Panels are unconditional where alerts are not: the in-chart staleness panel plots
every controller's last-tick age, while the staleness _alert_ ships only for the
declared tick producers in `alerts.tickProducerControllers`. A panel showing no
series is information; an alert on no series is a page. Curated panels here follow
the same rule, and they may only group by the bounded label vocabularies
(`controller`, `vendor`, `type`, `destructive`) documented in `../SIGNALS.md`.

- `overview.json` is the first curated dashboard and the target for alert panel
  links.
- Additional files are single-purpose deep dives linked from `overview.json`.
- Each file carries a deterministic `<platform>-<service>-<purpose>` UID.
- Every dashboard is linted, rendered in the sandbox, and visually inspected
  before merge.

The service's primordial chart emits one `GrafanaDashboard` per JSON file. See
the [dashboard standard](../../docs/standards/grafana-dashboards/index.md) and
[rendering convention](../../docs/standards/observability/primordial-chart.md).
