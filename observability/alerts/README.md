# Alert sets

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
