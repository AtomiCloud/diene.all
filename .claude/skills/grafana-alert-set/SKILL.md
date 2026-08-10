---
name: grafana-alert-set
description: Create or review one alert set — a folder bundling the alert family (1–3 tiers, minimal definitions) and its runbook — plus repo-level coverage and dedup across sets. Use when adding alerts for a signal, reviewing the service's alerts, or translating SIGNALS.md decisions into alert-set folders.
invocation:
  - alert-set
  - alerts
  - alert-portfolio
  - alert-coverage
  - rule-group
---

# Grafana Alert Set

One alert set = one folder: `observability/alerts/<alert-slug>/` containing **one flat file per tier** — `critical.yaml`/`warning.yaml`/`info.yaml` (the filename IS the severity; not everything needs tiers) — plus `runbook.md`. The folder structure is the enforcement: a set without its runbook fails the transformer. Write each tier file with `grafana-alert` starting from [templates/alert-template.yaml](./templates/alert-template.yaml), the runbook with `grafana-runbook`.

**These become Grafana-managed alerts, NOT `PrometheusRule` resources** — the service's primordial chart uses the reusable helm-wrapper transformer to derive all plumbing (severity/emoji from the filename, uids, CR wrapper, LPSM labels, runbook/dashboard links) per the Transformation Contract. The runtime app chart never renders them, and there is no central observability chart. There is deliberately no behavioral test (none exists for Grafana rules): validation = transformer structural checks + PR review checklist + Grafana Preview before merge.

Follow the authoritative set design (family/tier rules, cross-set dedup, noise budget in SIGNALS.md Gate 5, coverage) and the derivation table in **[observability/alerts.md](../../../docs/standards/observability/alerts.md)**.

Umbrella standard: [observability/](../../../docs/standards/observability/index.md)

Related skills: `grafana-alert` (each rule), `grafana-runbook` (the folder's runbook + overview), `observability-check` (what may become a set).
