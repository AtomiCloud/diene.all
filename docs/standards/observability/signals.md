# Signal Decisions (observability-check)

The gated decision cascade for deciding which observability signals a feature gets, and the `SIGNALS.md` record that captures the decisions. The defaults differ by signal: **metrics default to NO** (they cost active series forever); **logs and traces are deliberately liberal** (the platform manages their volume with adaptive sampling) — as long as they are event-driven, not spam.

---

## Cost model: strict on metrics, liberal on logs and traces

| Signal  | Cost unit                                                                                                                        | Stance                                                                                                                                      |
| ------- | -------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------- |
| Metrics | **Active time series (ATS)** — the memory/billing unit of the TSDB; product of label-value cardinalities, ×~10–15 for histograms | **Strict.** Estimate ATS before adding (`series = Π(label cardinalities) × buckets`); >100 ATS for one feature needs explicit justification |
| Logs    | Volume (lines × bytes × retention)                                                                                               | **Liberal.** The platform's adaptive sampling manages volume. Log generously — but event-driven, never unconditional hot loops              |
| Traces  | Span count (spans × traffic × retention)                                                                                         | **Liberal.** Same: adaptive/tail sampling manages volume. Trace user flows by default                                                       |

Cardinality bugs are still cost bugs: an unbounded label (user ID, URL, request ID) turns one metric into millions of ATS. Reject them at review — IDs belong in logs and trace attributes, where they are exactly what you want.

Attention cost still applies to alerts and dashboards: every panel and alert competes for a responder's focus. Logs and traces don't page anyone — that's why they get to be liberal.

---

## The Six Gates (walk in order, answer all, justify every answer)

### Gate 1 — Metrics? (default NO)

Say YES only if at least one holds:

- A human or automation **acts on the number** (threshold, capacity decision, scaling review)
- It feeds an **SLO**
- Debugging needs an **aggregate** that logs cannot answer (e.g. p99 latency)

If YES: name each metric, its type (counter/gauge/histogram), its labels, and its **estimated ATS**. Reject any label whose value set is unbounded. Prefer counters/gauges over histograms unless you need percentiles — a histogram is ~10–15× the series.

### Gate 2 — Logs? (default YES for events)

Log **liberally, driven by user/business events**: every meaningful event (request handled, job executed, state transition, decision taken, failure) gets a structured log carrying the **inputs and key variables** — the goal is that a debugger can reconstruct the **order of events and the values in play** without redeploying. The platform's adaptive sampling manages volume.

The one prohibition: **constant spam** — unconditional logs in hot loops, per-tick polling, per-item logs inside large batches. Those get aggregated into a metric or logged once per batch with counts. Record the expected volume for anything that could be high-frequency.

### Gate 3 — Traces? (default YES for user flows)

Trace **user-event flows by default**: a span per meaningful stage, attributes carrying the key IDs and variables (plus LPSM resource attributes), so latency and causality are reconstructible per request. Adaptive/tail sampling manages volume — note the intended policy (e.g. keep all errors, sample successes). Skip tracing only for internal machinery with no per-event flow worth following.

### Gate 4 — Dashboard panels? (default: generic tier is enough)

Standard signals (request rate/errors/duration, resource usage) are already covered by the generic LPSM dashboard — never re-add them. Only **custom/domain** metrics from Gate 1 may earn panels on the curated service dashboard; name the panel and its row (overview vs detail). No custom metrics → no curated dashboard — a valid, good outcome. See [Grafana Dashboards](../grafana-dashboards/index.md).

### Gate 5 — Alerts? (default NO)

For each approved signal, apply ALL alerting gates — fail any one → no alert:

1. **No self-healing**: does a mechanism auto-correct this (HPA/autoscaler, restart policy, retries)? If yes → NO alert on the condition; consider alerting on the **mechanism's exhaustion** instead (at max replicas AND still saturated; retries losing).
2. **Actionable**: a responder must have something concrete to do. "Watch it" → `info` at most.
3. **Routable**: LPSM labels will route it to the owning team.

If an alert survives: decide **tier count** (1 = binary failure, 2 = capacity/degradation default, 3 = only when the trend itself matters), the **alert type**, and the **noise budget** (expected fire rate, e.g. "≤2 pages/month" — if it will fire more often than someone acts, it fails the actionability gate) — see [Alerts](./alerts.md).

### Gate 6 — Runbook

Every alert from Gate 5 becomes an **alert-set folder** (`observability/alerts/<slug>/` with one file per tier — `critical.yaml`/`warning.yaml`/`info.yaml` — plus `runbook.md`) **before merge**. List the required folder slugs — slug = base name lowercased, spaces → hyphens, `[a-z0-9-]` only. See [Runbooks](./runbooks.md) and [Alerts](./alerts.md).

---

## The SIGNALS.md record

Lives at `observability/SIGNALS.md`, one block per feature. **The canonical fill-in skeleton is the `observability-check` skill's `templates/SIGNALS-template.md`** — the outline below defines what each gate must record:

```markdown
## Feature: <name> (<PR link / date>)

### Gate 1 — Metrics

**Decision:** NO | YES
**Justification:** <who acts on it / which SLO / what aggregate question>
| Metric | Type | Labels | Est. ATS | Why |

### Gate 2 — Logs

**Decision:** YES | NO (+ event table: Event, Level, Inputs/key variables, Est. volume)

### Gate 3 — Traces

**Decision:** YES | NO (+ span table: Span, Attributes, Sampling)

### Gate 4 — Dashboard

**Decision:** generic tier sufficient | curated panels (+ panel table)

### Gate 5 — Alerts

**Decision:** NO | YES
**Self-healing check:** <what mechanism exists and why it does not cover this>
**Noise budget:** <expected fire rate, e.g. ≤2 pages/month>
| Alert (base name) | Type | Tiers | Threshold(s) |

### Gate 6 — Alert-set folders required

- `alerts/<alert-slug>/`
```

A worked example:

| Question  | Decision                                                                                                                | Why                                                                                  |
| --------- | ----------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------ |
| Metrics   | ✅ `webhook_retry_queue_depth` (gauge, ~4 ATS), `webhook_delivery_failures_total` (counter, ~8 ATS)                     | Queue depth is capacity-relevant; failures feed error rate                           |
| Logs      | ✅ one structured event per delivery attempt (payload id, target, attempt #, outcome) + one ERROR per permanent failure | Event order + values reconstructible for debugging; adaptive sampling handles volume |
| Traces    | ✅ span per delivery attempt (ids as attributes); keep all errors, sample successes                                     | Per-request causality for slow/failed deliveries                                     |
| Dashboard | ✅ queue depth (detail row), failure rate (overview row)                                                                | Custom metrics — curated tier                                                        |
| Alerts    | ✅ 2-tier family on queue depth; ❌ none on retry _rate_                                                                | Retrying IS the self-healing — alert on the healer losing, not working               |
| Runbook   | `alerts/webhook-retry-queue/`                                                                                           |                                                                                      |

---

## Verification checklist (mechanical)

- [ ] `SIGNALS.md` has a block for the feature with **all six gates** answered
- [ ] Every answer has a one-line justification (a bare YES/NO fails review)
- [ ] Every YES names its artifact (metric / log event / span / panel / alert-set folder) **and its cost** (ATS estimate, log volume, sampling policy)
- [ ] Every "Gate 5 (Alerts) = YES" names tier count, alert type, AND noise budget
- [ ] Cross-check: each named artifact exists in the PR (grep the metric name in code; each Gate-6 folder exists under `observability/alerts/`)
- [ ] No unbounded labels on any metric; no unconditional hot-loop logs; sampling policy stated for traces
- [ ] No standard-signal panel added to a curated dashboard
