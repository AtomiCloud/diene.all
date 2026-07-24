# Signals — `{platform}`/`{service}`

Decision record from `observability-check`. Add one complete block per feature.
Metrics and alerts default to NO; event-driven logs and user-flow traces default
to YES. Every answer needs a justification and a cost estimate.

## Feature: `{feature name}` (`{PR link or date}`)

### Gate 1 — Metrics

**Decision:** NO | YES

**Justification:** `{who acts on the number, which SLO uses it, or which aggregate question it answers}`

| Metric   | Type                    | Labels             | Estimated ATS       | Why        |
| -------- | ----------------------- | ------------------ | ------------------- | ---------- |
| `{name}` | counter/gauge/histogram | `{bounded labels}` | `{series estimate}` | `{reason}` |

### Gate 2 — Logs

**Decision:** YES | NO

**Justification:** `{which user or business events are reconstructible from these logs}`

| Event                           | Level           | Inputs and key variables | Estimated volume   |
| ------------------------------- | --------------- | ------------------------ | ------------------ |
| `{event, decision, or failure}` | INFO/WARN/ERROR | `{bounded context}`      | `{lines/s or day}` |

### Gate 3 — Traces

**Decision:** YES | NO

**Justification:** `{which user or business flow is worth following}`

| Span          | Attributes                | Sampling                                |
| ------------- | ------------------------- | --------------------------------------- |
| `{span name}` | LPSM + `{bounded values}` | `{keep errors, sample successes, etc.}` |

### Gate 4 — Dashboard

**Decision:** generic tier sufficient | curated panels

**Justification:** `{custom metrics only; standard signals stay on the generic dashboard}`

| Panel     | Row             | Metric     |
| --------- | --------------- | ---------- |
| `{title}` | overview/detail | `{metric}` |

### Gate 5 — Alerts

**Decision:** NO | YES

**Self-healing check:** `{what already heals this condition, or why alerting on exhaustion is still required}`

**Noise budget:** `{expected fire rate, such as no more than two pages per month}`

| Alert base name | Type                                                           | Tiers | Thresholds |
| --------------- | -------------------------------------------------------------- | ----- | ---------- |
| `{symptom}`     | threshold/absence/event/burn-rate/deviation/prediction/outlier | 1/2/3 | `{values}` |

### Gate 6 — Alert-set folders required

- None, or `alerts/{alert-slug}/`
