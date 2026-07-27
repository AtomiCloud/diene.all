# Signals — `diene`/`fleet-operator`

Decision record from `observability-check`. One block per feature. Metrics and
alerts default to NO; event-driven logs and user-flow traces default to YES.
Every answer carries a justification and a cost estimate.

The default reconcile + fleet-taxonomy signals below ship today as chart
templates (`infra/root_chart/templates/{grafanaalertrulegroup,dashboard,metric-taxonomy}.yaml`),
enforced by `scripts/validate/operator-observability-artifacts.ts`. Per-controller
curated dashboards and alert sets are a Phase 4 concern: keep `dashboards/` and
`alerts/` as scaffolds until a Gate 4 / Gate 5 decision below approves a curated
artifact.

## Feature: Reconcile + fleet metric taxonomy (2026-07-27)

Every metric named here is registered by `adapters/operator/metrics/metrics.go`;
the chart alert pack and dashboard reference only these names.

### Gate 1 — Metrics

**Decision:** YES

**Justification:** the fleet-operator is one binary writing DNS every 5s and
provisioning external resources; on-call pages on reconcile failure, poll-loop
staleness, a tripped blast brake, ledger/vendor failures, and webhook
config-plane lag. Webhook delivery-path metrics are NOT here — mercury owns the
delivery path and exports those signals from its own app (Q-WH8), so this
operator registers no webhook delivery-event family and no delivery-state label
vocabulary.

| Metric                                                  | Type      | Labels                  | Estimated ATS                 | Why                                                           |
| ------------------------------------------------------- | --------- | ----------------------- | ----------------------------- | ------------------------------------------------------------- |
| `fleet_operator_condition`                              | gauge     | controller, type        | controllers × bounded types   | Conflict/Unresolved/Drifted/BlastBrakeTripped held True pages |
| `fleet_operator_ledger_failures_total`                  | counter   | controller              | controllers                   | durable-ledger write failures                                 |
| `fleet_operator_reconcile_ticks_total`                  | counter   | controller              | controllers                   | reconcile-loop liveness counter (rate view)                   |
| `fleet_operator_last_successful_tick_timestamp_seconds` | gauge     | controller              | controllers                   | poll-loop liveness as a TIMESTAMP; staleness = time() − value |
| `fleet_operator_vendor_api_failures_total`              | counter   | controller, vendor      | controllers × bounded vendors | DNS/vendor API error rate                                     |
| `fleet_operator_provisioning_duration_seconds`          | histogram | controller              | controllers × buckets         | provisioning-duration budget (p99)                            |
| `fleet_operator_webhook_compile_failures_total`         | counter   | controller              | 1 (webhook)                   | config-compile failures                                       |
| `fleet_operator_materialization_ack_lag_seconds`        | gauge     | controller              | 1 (webhook)                   | a landscape stuck behind `cfg:gen` pages                      |
| `fleet_operator_tenant_sync_failures_total`             | counter   | controller              | 1 (webhook)                   | internal-tenant management-API sync failures                  |
| `fleet_operator_plan_actions`                           | gauge     | controller, destructive | controllers × 2               | observe-mode would-apply plan surface (empty = healthy)       |

Framework metrics (`controller_runtime_reconcile_total`,
`controller_runtime_reconcile_errors_total`,
`controller_runtime_reconcile_time_seconds`) come for free from controller-runtime.

#### Bounded labels (how the ATS estimates above are actually enforced)

The estimates are not a hope about caller discipline: every public label value is
folded to a closed vocabulary **at the recorder boundary** in
`adapters/operator/metrics/metrics.go`, with one fixed overflow sentinel, `other`,
shared by all of them. An unknown, object-derived, or secret-bearing string
therefore adds at most one child series per family, is never exposed verbatim, and
never becomes a new label value.

| Label         | Vocabulary                                                                      | Worst case |
| ------------- | ------------------------------------------------------------------------------- | ---------- |
| `controller`  | 9 documented controllers (2 fenced samples + the 7 real enable seams) + `other` | 10         |
| `vendor`      | 5 documented vendors + `other`                                                  | 6          |
| `type`        | the pure `lib/operator/conditions` constant set (40 types) + `other`            | 41         |
| `destructive` | `true` / `false`                                                                | 2          |

The controller list covers every `--enable-*` seam the runtime declares, including
the reserved `problem` seam, which is not folded yet and emits nothing today. A
known future controller is listed deliberately: otherwise its first writer would
land on `other` and its series would be invisible until someone noticed. `note` and
`journal` stay listed only for source compatibility until the R1 sample deletion.

The controller and vendor vocabularies are declared once in the chart
(`infra/root_chart/values.yaml` → `metricLabels`), rendered into the
`metric-taxonomy` ConfigMap, and compared set-for-set against the Go recorder by
`scripts/validate/operator-observability-artifacts.ts`; the condition vocabulary is
compared by constant reference, so the recorder cannot respell or miss a pure
condition type. The validator also proves every `controller=` selector the chart
ships is a bounded value — a selector outside the vocabulary would match nothing,
because the recorder would have folded that controller to `other`.

Cardinality is bounded, not free: an unlisted condition type aggregates onto
`other`, so per-type state for an unlisted type is read from the CR status rather
than from Prometheus, and an unlisted vendor is identified from the
vendor-call-failure log line in Gate 2.

### Gate 2 — Logs

**Decision:** YES

**Justification:** every reconcile decision, ledger intent→create→confirm step,
vendor call, and brake trip is reconstructible from structured logs; the metrics
above are the alertable aggregates, logs carry the per-object detail.

| Event                                 | Level | Inputs and key variables                         | Estimated volume      |
| ------------------------------------- | ----- | ------------------------------------------------ | --------------------- |
| reconcile decision / would-apply plan | INFO  | controller, LPSM coordinate, action, destructive | per reconcile         |
| ledger intent/create/confirm          | INFO  | controller, coordinate, externalId, generation   | per external mutation |
| vendor / DNS call failure             | ERROR | controller, vendor, operation, error class       | on failure            |
| blast brake trip (freeze + page)      | ERROR | controller, cap, attempted, computed             | rare, load-bearing    |

### Gate 3 — Traces

**Decision:** NO

**Justification:** reconcile paths are level-triggered and short; the durable
ledger + structured logs already reconstruct the flow. Revisit if a
cross-controller provisioning journey needs span-level latency attribution.

### Gate 4 — Dashboard

**Decision:** generic tier (shipped in-chart) sufficient for Phase 2

**Justification:** the in-chart `dashboard.yaml` covers reconcile RED, condition
state, staleness, ledger/vendor failures, provisioning duration, the webhook
config-plane, and the observe-mode plan surface. Curated per-controller deep
dives land in `dashboards/` only when a controller's Phase 3/4 work needs panels
the generic dashboard cannot express.

| Panel                     | Row      | Metric                                                  |
| ------------------------- | -------- | ------------------------------------------------------- |
| Reconcile/poll staleness  | overview | `fleet_operator_last_successful_tick_timestamp_seconds` |
| Observe-mode plan actions | overview | `fleet_operator_plan_actions`                           |

### Gate 5 — Alerts

**Decision:** YES (default pack ships in-chart)

**Self-healing check:** reconcile retries and level-triggered re-derivation heal
transient faults; the alerts below fire only on persistence (`for` windows) or on
conditions that never self-heal (blast-brake freeze, poll-loop staleness).

**Noise budget:** steady state is zero pages; a healthy fleet in observe mode
holds an empty plan and no paging condition True. The staleness rule is the one
alert that pages on an EMPTY series, so it is rendered only for controllers
explicitly declared as producers of the timestamp gauge in the chart's
`alerts.tickProducerControllers` (default: empty, so no staleness rule ships at
all). A controller with no `MarkTick` writer — a fenced sample, or a real
controller whose poll loop has not landed — would otherwise page forever on a
deliberately empty series, which is a permanent false page, not liveness. For a
declared producer the strong `noDataState: Alerting` behavior is exactly right and
is preserved.

| Alert base name           | Type      | Tiers    | Thresholds                                                              |
| ------------------------- | --------- | -------- | ----------------------------------------------------------------------- |
| reconcile errors          | threshold | warning  | rate > 0 for 5m                                                         |
| reconcile latency p99     | threshold | warning  | > 10s for 10m                                                           |
| reconcile/poll staleness  | absence   | critical | declared tick producers only: time() − last-tick > 300s, no-data = page |
| persistent condition      | threshold | critical | Conflict/Unresolved/Drifted/BlastBrakeTripped True 15m                  |
| ledger failures           | threshold | warning  | rate > 0 for 5m                                                         |
| vendor/DNS API failures   | threshold | warning  | rate > 0 for 5m                                                         |
| provisioning duration p99 | threshold | warning  | > 300s for 15m                                                          |
| webhook compile failures  | threshold | warning  | rate > 0 for 5m                                                         |
| materialization/ack lag   | threshold | critical | > 300s for 10m                                                          |
| tenant-sync failures      | threshold | warning  | rate > 0 for 5m                                                         |

### Gate 6 — Alert-set folders required

- None yet. The default pack ships as the chart's `GrafanaAlertRuleGroup`.
  Add `alerts/{alert-slug}/` only when a Phase 3/4 controller needs a curated,
  runbook-backed alert set beyond the parameterized default.
