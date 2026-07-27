---
name: grafana-alert
description: Write one well-formed alert definition — severity, short title (≤48 chars, emoji derived), correct alert type (threshold, absence, event, burn-rate, deviation, prediction, outlier), summary/description, dashboard panel link. Use when writing, modifying, or reviewing a single alert rule.
invocation:
  - alert
  - alert-rule
  - alerting
  - grafana-alert
  - promql-alert
  - threshold
  - burn-rate
---

# Grafana Alert Rule

Produce ONE minimal alert definition as a flat file in its set's folder — `observability/alerts/<slug>/<severity>.yaml`, where **the filename is the severity** (`critical.yaml`/`warning.yaml`/`info.yaml`). Fields: `title` (plain symptom, ≤48 chars — the emoji prefix is derived), `datasource: metrics|logs`, the `expr` (chosen by alert type), `for`, `summary` (what + how bad, value templated in), `description` (what to do first), and `panel` (curated overview panel id, or omit for the generic dashboard). Everything else — severity/emoji, uid, Grafana plumbing, runbook/dashboard links, LPSM labels, the CR wrapper — is derived by the service's primordial-chart transformer per the Transformation Contract; these deploy as Grafana-managed alerts, NOT `PrometheusRule` resources. Creating the whole set (alerts + runbook)? Start from `grafana-alert-set`.

Copy the skeleton from `grafana-alert-set`'s [templates/alert-template.yaml](../grafana-alert-set/templates/alert-template.yaml).

Follow the authoritative contract, field semantics (where title/summary/description appear in UI/notifications), the type table with expr examples, and the Transformation Contract in **[observability/alerts.md](../../../docs/standards/observability/alerts.md)**.

Validate: the transformer fails on structural violations (a Helm implementation fails `helm template`); reviewers check the semantic rules; then **use Grafana's Preview before merge** — the only check that catches an alert that can never fire. State in the PR that Preview was done.

Umbrella standard (label model, folder layout): [observability/](../../../docs/standards/observability/index.md)

Related skills: `grafana-alert-set` (the folder), `grafana-runbook` (the runbook), `observability-check` (whether this alert should exist at all).
