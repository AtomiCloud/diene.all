# Signals — `<platform>`/`<service>`

Decision record from `observability-check`. One block per feature. Every gate answered, every answer justified and costed. Defaults: metrics and alerts NO; logs and traces YES for user/business events.

---

## Feature: `<feature name>` (<PR link / date>)

### Gate 1 — Metrics

**Decision:** NO | YES
**Justification:** <one line — who acts on this number / which SLO / what aggregate question>

| Metric   | Type                    | Labels             | Est. ATS                             | Why        |
| -------- | ----------------------- | ------------------ | ------------------------------------ | ---------- |
| `<name>` | counter/gauge/histogram | `<bounded labels>` | <series estimate; histograms ×10–15> | `<reason>` |

### Gate 2 — Logs (default YES for events)

**Decision:** YES | NO
**Justification:** <which user/business events; NO only if there is genuinely no event flow>

| Event                          | Level           | Inputs / key variables                                    | Est. volume                       |
| ------------------------------ | --------------- | --------------------------------------------------------- | --------------------------------- |
| `<event / decision / failure>` | INFO/WARN/ERROR | `<inputs + values needed to reconstruct order and state>` | <lines/s or /day; flag hot loops> |

### Gate 3 — Traces (default YES for user flows)

**Decision:** YES | NO
**Justification:** <which flows; NO only if no per-event flow worth following>

| Span          | Attributes                   | Sampling                                 |
| ------------- | ---------------------------- | ---------------------------------------- |
| `<span name>` | LPSM + `<key ids/variables>` | <e.g. keep all errors, sample successes> |

### Gate 4 — Dashboard

**Decision:** generic tier sufficient | curated panels
**Justification:** <custom metrics only — standard signals are on the generic dashboard>

| Panel     | Row             | Metric     |
| --------- | --------------- | ---------- |
| `<title>` | overview/detail | `<metric>` |

### Gate 5 — Alerts

**Decision:** NO | YES
**Self-healing check:** <what mechanism exists (HPA/retries/…) and why it does not cover this — or why alerting on its exhaustion instead>
**Noise budget:** <expected fire rate, e.g. ≤2 pages/month>

| Alert (base name) | Type                                                           | Tiers | Threshold(s)                  |
| ----------------- | -------------------------------------------------------------- | ----- | ----------------------------- |
| `<symptom>`       | threshold/absence/event/burn-rate/deviation/prediction/outlier | 1/2/3 | `<warning @ X, critical @ Y>` |

### Gate 6 — Alert-set folders required

- `alerts/<alert-slug>/`
