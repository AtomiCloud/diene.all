---
name: grafana-dashboards
description: Author and self-verify Grafana dashboards as code — two-tier model (generic LPSM dashboard vs curated custom-metrics dashboards), RED/USE layout, then lint, render, and visually inspect the result in a sandbox before shipping. Use when creating or modifying Grafana dashboards, dashboard JSON, panels, or template variables.
invocation:
  - dashboard
  - dashboards
  - grafana-dashboard
  - panel
  - panels
  - red-dashboard
  - use-dashboard
  - visualization
  - grafana
---

# Grafana Dashboard Authoring & Self-Verification

**Never ship a dashboard you have not seen rendered.** Decide the tier first (generic LPSM dashboard covers standard signals; curated `observability/dashboards/<purpose>.json` files are earned only by custom metrics — `overview.json` is what alerts link to), author as code, then prove it: `jq` → `dashboard-linter --strict` → docker sandbox with synthetic data → render PNGs → inspect against the visual checklist → iterate. Every panel an alert references (its `panel` field) must exist in `overview.json` — dashboards are IaC; reviewers check the reference.

Follow the authoritative two-tier model, authoring rules, verification loop, and visual checklist in **[grafana-dashboards/index.md](../../../docs/standards/grafana-dashboards/index.md)**; sandbox compose files and the synthetic-data recipe are in **[sandbox.md](../../../docs/standards/grafana-dashboards/sandbox.md)**.

Umbrella standard (label model, folder layout): [observability/](../../../docs/standards/observability/index.md)

Naming/UIDs follow the Service Tree (LPSM) conventions — use the `service-tree` skill when available.
