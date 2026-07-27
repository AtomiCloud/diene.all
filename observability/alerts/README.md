# Alert sets

The fleet-operator's default alert pack (reconcile RED, timestamp-staleness
liveness, persistent conditions incl. `BlastBrakeTripped`, ledger/vendor
failures, provisioning duration, and the webhook config-plane) ships today as the
chart's parameterized `GrafanaAlertRuleGroup`. This folder is reserved for curated
Gate 5 alert sets a Phase 3/4 controller needs beyond that default — keep it a
scaffold until such a decision lands in `../SIGNALS.md`.

The timestamp-staleness rule is the one member of that pack that pages on an
absent series (`noDataState: Alerting`), which is correct for a real poll loop and
a permanent false page for anything else. It is therefore rendered only for the
controllers declared in the chart's `alerts.tickProducerControllers` — the
controllers that actually write `MarkTick`. The default is empty, so a fresh
install ships no staleness rule; add a controller there in the same change that
lands its tick writer. Both the empty-default and declared-producer renders are
asserted by `../../scripts/validate/operator-observability-artifacts.ts`, so the
rule can neither page on nothing nor silently disappear.

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
