# Alert Rules and Alert Sets

How to write one well-formed alert (the contract), how to choose the alert type, and how alert sets are organized.

Whether an alert should exist at all is decided upstream — see [Signal Decisions](./signals.md), Gate 5.

## The unit of work: one alert set = one folder

An **alert set** is one measured thing (a signal family) with 1–3 severity tiers, plus its runbook — bundled in one folder so the runbook can't be forgotten:

```text
observability/alerts/<alert-slug>/
├── critical.yaml       # ONE FILE PER TIER — the filename IS the severity
├── warning.yaml        #   (info.yaml for a third tier; delete files you don't need)
└── runbook.md          # THE runbook for this alert — see Runbooks
```

- **The filename is the severity**: `critical.yaml` / `warning.yaml` / `info.yaml`. No severity field exists, so a severity/emoji mismatch is unrepresentable, and the filesystem enforces at most one rule per tier.
- **Not everything needs tiers**: 1 file (critical only) for binary failures; 2 for capacity/degradation; 3 only when the trend itself is worth recording. A single-file set is perfectly normal.
- Tiered files share the base symptom title and the folder's runbook.
- Thresholds between tiers need real gaps (>20% apart) — tiers closer than that are one alert pretending to be two.

**Slug** = the alert base name, lowercased, spaces → hyphens, `[a-z0-9-]` only (`Webhook retry queue` → `webhook-retry-queue`). It names the folder and everything derived from it.

Repo-level rules across sets: every "Gate 5 (Alerts) = YES" row in `SIGNALS.md` has a folder, and every folder traces back to SIGNALS.md — a repo whose SIGNALS.md has no Gate-5 YES has no `alerts/` directory at all, which is a valid outcome. De-duplicate across sets — if two sets can fire for the same root cause, keep the user-facing SYMPTOM as the pager and demote or delete the cause-side one. A burn-rate set usually replaces 2–3 hand-rolled error/latency threshold sets. The expected noise budget (e.g. "≤2 pages/month") is recorded in SIGNALS.md Gate 5.

## Format: one flat file per tier — pure Grafana-domain, no Kubernetes

Alert definitions are **Grafana-domain objects**: authors never write Kubernetes wrappers, CR plumbing, or LPSM labels. Each tier file is a single flat YAML dictionary:

```yaml
# observability/alerts/webhook-retry-queue/critical.yaml   (the filename IS the severity)
title: Webhook retry queue saturated # plain symptom — emoji is derived from the filename
datasource: metrics # metrics (PromQL) | logs (LogQL)
expr: webhook_retry_queue_depth{service="zinc"} > 5000
for: 10m
summary: 'Retry queue at {{ $values.A }} — deliveries dropping'
description: 'Check downstream health — queue drains only if endpoints are up.'
panel: 2 # panel in dashboards/overview.json; omit → links the generic dashboard
```

Copy the skeleton from the `grafana-alert-set` skill's `templates/alert-template.yaml`.

## The Transformation Contract

The standard specifies the mapping implemented by the reusable primordial-chart helper. The service's primordial chart reads the folder and produces **Grafana-managed alerts** (NOT `PrometheusRule` resources — no Prometheus/Mimir ruler is involved), deriving:

| Derived                                                                                                                                                                                                                                                       | From                                                                                                                             |
| ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------- |
| `severity` label + 🚨/⚠️/ℹ️ title prefix                                                                                                                                                                                                                      | the **filename** — a mismatch is unrepresentable                                                                                 |
| Rule `uid`                                                                                                                                                                                                                                                    | `<slug>-<severity>`                                                                                                              |
| Grafana rule plumbing (`condition: A`, `refId: A`, `data`, `relativeTimeRange`, `noDataState: OK`, `execErrState: Error`, instant query)                                                                                                                      | fixed                                                                                                                            |
| `datasourceUid`                                                                                                                                                                                                                                               | `datasource: metrics \| logs` → the platform's pinned UIDs                                                                       |
| `runbook_url`                                                                                                                                                                                                                                                 | the repo's https URL + `observability/alerts/<slug>/runbook.md` — always this set's own runbook                                  |
| `__dashboardUid__` + `__panelId__`                                                                                                                                                                                                                            | `panel` present → the curated overview (`<platform>-<service>-overview`) + that panel; absent → the platform's generic dashboard |
| **LPSM labels** (built in — never authored)                                                                                                                                                                                                                   | the deployment context (chart values / central config), merged into the rule's labels dict                                       |
| **One file → one CR**: group name `<platform>-<service>-<slug>-<severity>`, `rules` list with exactly one element, `folderRef` (`<platform>-<service>-folder` — the app folder uid; the `-folder` suffix keeps it out of the shared dashboard/group uid pool) | service tree + folder name + filename — no grouping or array assembly anywhere                                                   |

**Golden example** — the conformance fixture. The `critical.yaml` above, in service tree `{landscape: raichu, platform: tracker, service: zinc, module: webhook}`, MUST become exactly:

```yaml
apiVersion: grafana.integreatly.org/v1beta1
kind: GrafanaAlertRuleGroup
metadata:
  name: tracker-zinc-webhook-retry-queue-critical # one file → one CR
spec:
  folderRef: tracker-zinc-folder
  interval: 1m
  rules: # always exactly ONE element — written inline, never assembled
    - uid: webhook-retry-queue-critical
      title: 🚨 Webhook retry queue saturated
      condition: A
      for: 10m
      noDataState: OK
      execErrState: Error
      data:
        - refId: A
          relativeTimeRange: { from: 600, to: 0 }
          datasourceUid: mimir
          model: { expr: 'webhook_retry_queue_depth{service="zinc"} > 5000', instant: true }
      labels:
        severity: critical
        landscape: raichu
        platform: tracker
        service: zinc
        module: webhook
      annotations:
        summary: 'Retry queue at {{ $values.A }} — deliveries dropping'
        description: 'Check downstream health — queue drains only if endpoints are up.'
        runbook_url: https://github.com/atomicloud/tracker-zinc/blob/main/observability/alerts/webhook-retry-queue/runbook.md
        __dashboardUid__: tracker-zinc-overview
        __panelId__: '2'
```

**The deployment home is fixed** — the service's own primordial chart includes the helm-wrapper helper and deploys these resources to Primordial. The app chart stays pure runtime; there is no central many-repository observability chart. The one-file-per-tier + one-file-per-CR mapping keeps the implementation trivial: a single `.Files.Glob` loop where each file (`fromYaml` → a _dict_, never an array) emits one complete manifest; label injection is a native dict merge — e.g. `mergeOverwrite (dict "severity" (base $path | trimSuffix ".yaml")) $.Values.serviceTree` — and the `rules` list always has exactly one inline element. No array assembly, no grouping logic, no structural YAML surgery anywhere. See [Primordial-Chart Rendering](./primordial-chart.md).

**Multi-datasource rules** (one condition over metrics AND logs) don't fit the minimal schema — and usually shouldn't exist: decompose into two single-signal alerts. A set that truly needs one ships a justified raw `GrafanaAlertRuleGroup` from the same service-owned primordial chart.

---

## The Rule Contract

### 1. It passed Gate 5 (Alerts)

The existence gates — no self-healing, actionable, routable — are owned by [Signal Decisions](./signals.md); an alert that isn't a Gate-5 YES in `SIGNALS.md` must not exist. The self-healing gate in practice:

| Condition                             | Self-healing exists? | Alert?                                 |
| ------------------------------------- | -------------------- | -------------------------------------- |
| CPU 80%, HPA/autoscaler enabled       | ✅ autoscaling       | ❌ — scaling is the response           |
| CPU 80%, no autoscaler                | ❌                   | ✅ `warning` (+ forecast tier)         |
| Autoscaler at max AND still saturated | mechanism exhausted  | ✅ `critical` — the self-healer failed |
| Single pod restart                    | ✅ restart policy    | ❌; sustained crash-loop → ✅          |
| Retry queue growing _despite_ retries | mechanism losing     | ✅                                     |

Actionability reminder: the runbook says what to DO — "watch it" → demote to `info` or delete.

### 2. Correct type for the signal shape

The type determines the `expr` (and occasionally the datasource). Everything else is boilerplate.

| Type                      | expr shape                                                                                                         | Best for                                                                                                            | Avoid when                                              |
| ------------------------- | ------------------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------- |
| **Static threshold**      | `metric > N` + `for` duration                                                                                      | Known hard limits without self-healing: disk %, queue depth, cert expiry                                            | Seasonal metrics (threshold lies twice a day)           |
| **Absence / heartbeat**   | `absent(metric)` or `rate(metric[15m]) == 0`                                                                       | Scrape target gone, cron didn't run, consumer silent                                                                | Flaky scrapes — fix the scrape first                    |
| **Event-based (LogQL)**   | `sum(count_over_time({service="x"} \| json \| level="ERROR" \|= "panic" [5m])) > 0`, `for: 0m`, `datasource: logs` | Discrete events: panics, OOMKills, security/corruption markers                                                      | A metric counterpart exists (prefer the metric)         |
| **SLO burn-rate**         | Multi-window error-ratio (below)                                                                                   | THE preferred pager: user-facing error/latency symptoms                                                             | Non-user-facing internals                               |
| **Seasonal deviation**    | `metric / metric offset 1w > 1.3` **and** absolute floor + smoothing                                               | Traffic-shaped metrics vs last week/month: volume, cost, throughput                                                 | <2 weeks of history, or no absolute floor               |
| **Prediction / forecast** | `predict_linear(metric[6h], 4*3600) < limit` + static backstop rule                                                | Slow-moving resources — act before impact: disk-full-in-4h, quota                                                   | Fast/spiky metrics (linear fit is meaningless)          |
| **Outlier**               | value − group avg > 3 × group `stddev`, ≥4 peers                                                                   | One instance unlike its peers, where the group defines normal                                                       | Small groups — no statistical peer set                  |
| **Mixed (metric + log)**  | multi-query: `A` = PromQL metric, `B` = LogQL, combined in a condition (`$A > N && $B > 0`)                        | Corroborate before paging — "error-rate up **and** error logs present"; suppress a metric blip with no log evidence | Either signal alone is sufficient (use its single type) |

Type-specific expr examples:

**SLO burn-rate** (99.9% SLO → error budget 0.001; plain PromQL, no special tooling):

```text
# 🚨 fast burn: both windows above 14.4× budget → pages within minutes of a real burn
( sum(rate(http_requests_total{service="zinc",status=~"5.."}[5m]))
  / sum(rate(http_requests_total{service="zinc"}[5m])) ) > (14.4 * 0.001)
and
( sum(rate(http_requests_total{service="zinc",status=~"5.."}[1h]))
  / sum(rate(http_requests_total{service="zinc"}[1h])) ) > (14.4 * 0.001)

# ⚠️ slow burn: 6× budget over 30m and 6h → ticket
```

Log-based services: the same shape in LogQL (`sum(rate({service="zinc"} | status >= 500 [5m])) / sum(rate({service="zinc"}[5m]))`) with `datasource: logs`. Trace signals: alert on span-derived metrics (the tracing pipeline's RED metrics) — TraceQL alerting exists but is experimental and not for production.

**Seasonal deviation** (both guards mandatory — absolute floor and smoothing):

```text
(
  avg_over_time(sum(rate(webhook_deliveries_processed_total{service="zinc"}[5m]))[1h:])
  /
  avg_over_time(sum(rate(webhook_deliveries_processed_total{service="zinc"}[5m]))[1h:] offset 1w)
) < 0.5
and
avg_over_time(sum(rate(webhook_deliveries_processed_total{service="zinc"}[5m]))[1h:] offset 1w) > 1
```

**Prediction + backstop** (never rely on the forecast alone — pair it with a plain threshold rule):

```text
predict_linear(dlq_disk_free_bytes{service="zinc"}[6h], 4*3600) < 0     # ⚠️ full in <4h
dlq_disk_used_ratio{service="zinc"} > 0.95                              # 🚨 backstop
```

**Outlier** (peer deviation, ≥4 peers):

```text
(
  webhook_delivery_duration_seconds{service="zinc", quantile="0.99"}
  - on() group_left avg(webhook_delivery_duration_seconds{service="zinc", quantile="0.99"})
)
> on() group_left 3 * stddev(webhook_delivery_duration_seconds{service="zinc", quantile="0.99"})
```

**Mixed (metric + log)** — two queries against two datasources, combined so the alert fires only when
BOTH conditions hold. Cuts false pages: a metric blip with no corroborating error logs (or a log spike
a healthy metric contradicts) doesn't page.

```text
# refId A — datasource: metrics — the metric symptom
A: sum(rate(http_requests_total{service="zinc",status=~"5.."}[5m]))
   / sum(rate(http_requests_total{service="zinc"}[5m])) > 0.05
# refId B — datasource: logs — corroborating evidence
B: sum(count_over_time({service="zinc"} | level="error" [5m])) > 0
# condition — a math/expression node combining them
C: $A && $B
```

Grafana evaluates each query against its own datasource, then a reduce/math node combines them into the
rule condition. This needs the **multi-query rule contract** — a `queries:` list (each with its own
`datasource` + `expr`) and an explicit combining `condition`, NOT the single `datasource`/`expr` a
one-signal tier carries. **Transformer note:** the `observability-lib` transformer today emits a single
instant query per tier (`condition: A`), so it renders single-datasource metric and log alerts but not
yet mixed ones — a mixed alert requires extending the transformer per the
[Transformation Contract](#the-transformation-contract) (multi-query `data:` + condition). Author mixed
alerts only once that support lands; until then, a metric alert plus a sibling log alert in the same set
is the portable approximation.

### 3. Title — short symptom (≤48 chars, no emoji)

**The title becomes the notification title** — what shows on a locked phone screen and in a Slack line, prefixed with the severity emoji by the transformer (🚨 critical / ⚠️ warning / ℹ️ info — derived from the tier filename; shape-distinct, colorblind-safe). Keep the authored title **≤48 characters** so the final title stays ≤50. Front-load the symptom: `Retry queue saturated`, not `The webhook delivery retry queue has become saturated`. No LPSM in the title; no query values (they go in `summary`).

The `severity` field stays the machine-readable source of truth — search, route, and silence by label, never by emoji. Re-tiering renames the alert — silences on the old name die; accept knowingly.

### 4. summary and description — each has a distinct job

| Field         | Where the responder sees it                                                       | So write it as                                                                                |
| ------------- | --------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------- |
| _(title)_     | **Notification title** — lock screen, Slack line, alert list row                  | The symptom, ≤48 chars                                                                        |
| `summary`     | **First line of the notification body** and the alert list — the compact surfaces | One line: symptom + magnitude; template the value in with `{{ $values.A }}`                   |
| `description` | The **alert detail view** and the expanded notification body — read after opening | Context + the first action to take ("Check downstream health — queue drains only if X is up") |

Rule of thumb: **title = what**, **summary = what + how bad**, **description = what to do first**, **panel = what it looks like**. If summary and description say the same thing, the description is wasted.

### 5. Every alert links a dashboard panel

A responder's first move is looking at the signal, not reading. The `panel` field controls the link the transformer emits:

- **`panel: <id>`** — the alert lands on that panel of the curated overview dashboard (`observability/dashboards/overview.json`). The panel must exist there — dashboards are IaC; reviewers check the id (see Validation).
- **`panel` omitted** — the alert links the platform's generic dashboard (standard signals: RED, resources), pre-filtered by LPSM.

---

## Validation

There is no behavioral test for Grafana alert rules (deliberate simplicity trade — revisit if a dead alert ever bites). Three layers, no code in this repo:

1. **The primordial-chart transformer validates structurally** — it refuses to produce output on: missing required fields (`title`/`datasource`/`expr`/`summary`/`description`), unknown tier filename (only `critical.yaml`/`warning.yaml`/`info.yaml`), title >48 chars, missing `runbook.md` in the folder. The Helm helper uses `required`/`fail`, so `helm template` fails in CI and on every render.
2. **PR review checklist (semantic)** — tier thresholds >20% apart; `panel` points at the right panel id in `overview.json`; runbook and overview sections complete; every SIGNALS.md Gate-6 folder exists and vice versa; slug is lowercase-kebab.
3. **Preview before merge (manual)**: open the rule in Grafana (sandbox or dev stack) and use **Preview** to confirm the query returns data and the condition evaluates — the only check that catches an alert that can never fire (typo'd metric name, impossible threshold). State in the PR that Preview was done.
