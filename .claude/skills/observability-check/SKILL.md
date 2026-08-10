---
name: observability-check
description: Decide which observability signals a feature needs — metrics, logs, traces, dashboard panels, alerts, runbook — via a gated decision cascade: strict on metrics and alerts (default NO, they cost series and attention), liberal on logs and traces (event-driven, capture inputs and key variables; adaptive sampling manages volume). Use when adding a feature, reviewing a PR for observability, auditing a service's instrumentation, or asked "is this observable enough".
invocation:
  - observability
  - observability-check
  - signals
  - instrument
  - instrumentation
  - telemetry
---

# Observability Check

Walk the feature through the six gates **in order** (metrics → logs → traces → dashboard → alerts → runbook), recording every answer, justification, and cost estimate in `observability/SIGNALS.md`. Metrics and alerts default NO; logs and traces default YES for user/business events — capture inputs and key variables so event order and values are reconstructible.

Follow the authoritative procedure — gates, cost rules of thumb, worked example, and verification checklist — in **[observability/signals.md](../../../docs/standards/observability/signals.md)**.

- Start from the template: [templates/SIGNALS-template.md](./templates/SIGNALS-template.md)
- Output: a filled `SIGNALS.md` block + a work list for `grafana-dashboards`, `grafana-alert-set` (→ `grafana-alert`), and `grafana-runbook`

Umbrella standard: [observability/](../../../docs/standards/observability/index.md)
