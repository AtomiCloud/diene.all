---
name: grafana-runbook
description: Write the per-alert runbook (Triage/Remediation/Escalation, copy-pasteable commands) that lives in the alert-set folder, and maintain the shared system overview (what it does, dependencies, failure modes, common commands). Use when writing or updating a runbook or overview.md, when an alert set lacks a runbook, or after an incident revealed a runbook gap.
invocation:
  - runbook
  - runbooks
  - triage
  - remediation
  - incident-response
  - overview
---

# Grafana Runbook

Every alert set has its own `observability/alerts/<slug>/runbook.md`; shared context lives once in `observability/overview.md` — runbooks link to it, never repeat it. Write for a half-awake responder: copy-pasteable commands, judgment calls spelled out, every fix ending with "Confirm with: …".

Follow the authoritative structures — the per-alert runbook (Triage/Remediation/Escalation) and the system overview (What it does / How it works / Dependencies / Failure modes / Common commands / Links) — in **[observability/runbooks.md](../../../docs/standards/observability/runbooks.md)**.

- Runbook template: [templates/runbook-template.md](./templates/runbook-template.md)
- Overview template: [templates/overview-template.md](./templates/overview-template.md)
- Validate: the transformer fails a set missing its runbook.md; section completeness is a PR-review check

Umbrella standard: [observability/](../../../docs/standards/observability/index.md)

Related skills: `grafana-alert-set` (the folder this lives in), `grafana-alert` (whose `runbook_url` points here).
