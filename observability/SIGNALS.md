# Signals — `diene`/`bunconsumer`

Decision record from `observability-check`. Add one complete block per feature.
Metrics and alerts default to NO; event-driven logs and user-flow traces default
to YES. Every answer needs a justification and a cost estimate.

Series estimates below assume the base shape: 2 worker replicas per landscape,
5 landscapes.

## Feature: `message consume → side-effect` (2026-07-25)

The domain sample: one worker handler reads an entry from the redis-streams
consumer group, performs its side effect against postgres and the object store,
and acknowledges. Everything the template proves — the message journey, the
health subcommand, the OTEL export — flows through this one path.

### Gate 1 — Metrics

**Decision:** YES — narrowly, two families.

**Justification:** The health metric is a hard requirement of the template
contract (`health metric` is a probe row) and answers a question no other signal
can: the Kubernetes exec probe restarts one wedged pod silently, so without an
exported gauge nobody learns the **workload** is degraded rather than one pod.
The processed counter is the on-call's first question when "the side effects
stopped appearing" — is the consumer stalled, or are producers not producing? A
log query can answer that only by counting lines over a window, which is exactly
what a counter is for, and it is the denominator any future burn-rate SLO needs.

| Metric                           | Type    | Labels                                             | Estimated ATS         | Why                                                                                                           |
| -------------------------------- | ------- | -------------------------------------------------- | --------------------- | ------------------------------------------------------------------------------------------------------------- |
| `bunconsumer.health`             | gauge   | LPSM only (0/1)                                    | 1/pod → **10** series | the `health` subcommand's verdict, exported. Distinguishes "one pod restarting" from "the workload is wedged" |
| `bunconsumer.messages.processed` | counter | LPSM + `outcome` ∈ {`ack`,`retry`,`fail`} (closed) | 3/pod → **30** series | consume throughput and failure ratio; the stall-vs-no-input question, and the SLO denominator                 |

Total added active series: **≈40**.

**Rejected — consumer-group lag / pending-entry count.** It is the
**transport's** number, not the app's: Upstash and Dragonfly already expose
`XPENDING` depth, and a consumer cannot measure the backlog it is failing to
read. Duplicating it in the app would add series without adding an answer, and it
would go stale exactly when it matters (a fully stalled worker stops reporting).
Read it from the dependency.

**Rejected — per-message-type or per-stream labels.** The label set is
producer-controlled and therefore unbounded. Message type belongs on the log line
and the span, where cardinality is free.

**Rejected — handler duration histogram.** No latency SLO exists for this worker,
and the consume flow is already traced. A histogram would multiply series for a
question traces answer better today. Revisit when a latency SLO is written.

### Gate 2 — Logs

**Decision:** YES

**Justification:** The whole business flow is reconstructible from these events:
which entry arrived, what the handler decided, whether it acked, and why it
failed. There is no HTTP access log to fall back on, so for a worker these lines
_are_ the audit trail. Levels follow the semantics, not the severity of the
author's mood: a retryable failure is WARN because the consumer group will
re-deliver it, and only a terminal failure is ERROR.

| Event              | Level | Inputs and key variables                                                      | Estimated volume                           |
| ------------------ | ----- | ----------------------------------------------------------------------------- | ------------------------------------------ |
| `message.received` | INFO  | `message.id`, `stream`, `consumer.group`, `delivery.count`                    | 1 per entry — the consume rate             |
| `message.acked`    | INFO  | `message.id`, `outcome`, side-effect ids written                              | 1 per successful entry                     |
| `message.failed`   | WARN  | `message.id`, `delivery.count`, error `type` URI + `title`, bounded `data`    | 1 per failed delivery — normally near zero |
| `message.terminal` | ERROR | `message.id`, `delivery.count`, error `type` URI — the entry is a poison pill | rare; each one is a human action           |
| `dbinit.step`      | INFO  | `step` ∈ {reachability, bucket, migrate, seed}, `outcome`, duration           | ~4 lines per rollout                       |
| `dbinit.failed`    | ERROR | `step`, error `type` URI + `title`                                            | rare; blocks the rollout                   |

Errors carry the RFC 7807 `type` URI and `title` from the problem catalog (R14),
so a log line links straight to the error portal. No message **payload** is ever
logged — only its id and the bounded fields the handler decided on.

### Gate 3 — Traces

**Decision:** YES

**Justification:** The consume flow crosses four systems (stream → postgres →
object store → ack) with no HTTP request to hang a trace off. When a side effect
is missing or slow, the span tree is the only artifact that says which hop
lost it. Producer context propagates in the stream entry, so a trace spans the
producer and this consumer end to end.

| Span                    | Attributes                                                              | Sampling                                           |
| ----------------------- | ----------------------------------------------------------------------- | -------------------------------------------------- |
| `consume {stream}`      | LPSM + `messaging.*` semconv, `message.id`, `delivery.count`, `atomi.*` | always keep errors; tail-sample successes          |
| `handle {message.type}` | LPSM + `message.type`, `outcome`                                        | child of `consume`; inherits the parent's decision |
| `sideeffect.postgres`   | LPSM + `db.*` semconv (statement summary, never bound values)           | child; inherits                                    |
| `sideeffect.store`      | LPSM + `aws.s3`-shaped attrs, bucket + object key                       | child; inherits                                    |
| `dbinit.{step}`         | LPSM + `step`, `outcome`                                                | always keep — a handful of spans per rollout       |

Semconv mapping plus `atomi.*` attributes per R14; the exporter is off by default
and enabled per landscape.

### Gate 4 — Dashboard

**Decision:** generic tier sufficient

**Justification:** The two custom metrics are single-line, standard-shaped series
that the generic LPSM dashboard already renders from its `platform`/`service`/
`module`/`landscape` variables. The worker has no HTTP RED signals and no
saturation surface of its own, so a curated dashboard would be two panels
duplicating the generic one. **No `dashboards/*.json` is added** — the scaffold's
rule is explicit that a placeholder dashboard must not be created to populate a
directory. Revisit when a curated panel would answer a question the generic
dashboard cannot; that is also the point at which alerts could carry
`__dashboardUid__`/`__panelId__` references.

| Panel                 | Row | Metric |
| --------------------- | --- | ------ |
| _none — generic tier_ | —   | —      |

### Gate 5 — Alerts

**Decision:** NO

**Self-healing check:** Every condition this feature can reach already heals, and
heals faster than a human could respond:

| Condition         | Self-healing                                                                                  | Alert?                                         |
| ----------------- | --------------------------------------------------------------------------------------------- | ---------------------------------------------- |
| worker wedged     | liveness exec probe on `health` restarts the pod; pending entries are re-delivered            | ❌ the restart **is** the response             |
| handler failure   | the entry stays unacked; the consumer group re-delivers it                                    | ❌ retry is the response                       |
| pod not ready     | readiness exec probe holds it out; the rollout stalls rather than proceeding                  | ❌ the rollout gate is the response            |
| dependency blip   | probes are dependency-blind by design, so the workload degrades instead of evicting           | ❌ the dependency owns its own alerting        |
| migration failure | the `PreSync` hook fails closed — the previous revision keeps running, CD reports red         | ❌ the pipeline already pages whoever deployed |
| poison message    | not self-healing, but the actionable symptom is a **pending backlog**, owned by the transport | ❌ see below                                   |

The one genuinely non-self-healing condition — a poison message consuming a retry
slot indefinitely — surfaces as pending-entry growth, and pending depth is the
transport's metric (Gate 1). Alerting on it from here would be a cause-side alert
against a number this service does not own, which the standard says to demote or
delete in favour of the user-facing symptom.

**Noise budget:** n/a — no alert shipped. There is no threshold this service can
currently evaluate that a human must act on within minutes, so `alerts/` stays
empty. That is a valid outcome, and the primordial chart renders cleanly with
zero alert sets.

Re-open this gate when a real SLO exists (then a burn-rate set on
`bunconsumer.messages.processed{outcome="fail"}` replaces two or three threshold
sets), or when the platform owns a pending-depth signal that a consumer-side
symptom alert can reference.

### Gate 6 — Alert-set folders required

- None.
