# Observability source

This directory is the service-owned source of truth for signal decisions,
dashboards, alerts, and runbooks. Keep it at the repository root. The service's
primordial chart copies this directory into its chart build context and renders
Grafana Operator resources on Primordial; the runtime app chart never renders
these files.

```text
observability/
├── README.md
├── SIGNALS.md
├── overview.md
├── dashboards/
│   └── README.md
└── alerts/
    └── README.md
```

The fleet-operator's default reconcile + fleet-taxonomy alert pack, dashboard,
and metric taxonomy currently ship as chart templates
(`infra/root_chart/templates/{grafanaalertrulegroup,dashboard,metric-taxonomy}.yaml`),
proven by `scripts/validate/operator-observability-artifacts.ts`. This directory
holds the signal DECISIONS (`SIGNALS.md`, `overview.md`) and is the home for any
future curated per-controller dashboards and alert sets.

The empty `dashboards/` and `alerts/` scaffold is intentional — that curation is
a Phase 4 concern. Do not add a placeholder dashboard or alert just to populate a
directory:

- Record every feature's six-gate decision in `SIGNALS.md`.
- Add `dashboards/overview.json` only when Gate 4 approves custom panels.
- Add `alerts/<slug>/<severity>.yaml` and `alerts/<slug>/runbook.md` only when
  Gate 5 approves an actionable alert.
- Keep alert definitions and dashboard JSON free of Kubernetes wrappers and
  hand-authored LPSM labels. The primordial-chart renderer supplies them.

The normative contracts are:

- [Observability standards](../docs/standards/observability/index.md)
- [OpenTelemetry alignment](../docs/standards/observability/otel.md)
- [Faro frontend variant](../docs/standards/observability/faro.md)
- [Primordial-chart rendering](../docs/standards/observability/primordial-chart.md)
