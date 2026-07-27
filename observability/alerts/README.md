# Alert sets

The fleet-operator's default alert pack (reconcile RED, timestamp-staleness
liveness, persistent conditions incl. `BlastBrakeTripped`, ledger/vendor
failures, provisioning duration, and the webhook config-plane) ships today as the
chart's parameterized `GrafanaAlertRuleGroup`. This folder is reserved for curated
Gate 5 alert sets a Phase 3/4 controller needs beyond that default — keep it a
scaffold until such a decision lands in `../SIGNALS.md`.

Create one folder per approved Gate 5 alert:

```text
alerts/
└── {alert-slug}/
    ├── critical.yaml
    ├── warning.yaml
    └── runbook.md
```

Only the required severities should exist. The severity is the filename; alert
files do not declare severity, routing, Kubernetes metadata, or LPSM labels.
Each YAML file is one flat Grafana-domain rule definition and becomes exactly
one `GrafanaAlertRuleGroup` in the service's primordial chart.

Every set must include its own `runbook.md`. Follow the
[alert contract](../../docs/standards/observability/alerts.md) and
[runbook contract](../../docs/standards/observability/runbooks.md).
