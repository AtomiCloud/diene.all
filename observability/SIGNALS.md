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
config-plane lag. Delivery-path webhook metrics are NOT here — those are
mercury's own in-app exports (Q-WH8), so no `fleet_operator_webhook_events_total`
family exists.

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
holds an empty plan and no paging condition True.

| Alert base name           | Type      | Tiers    | Thresholds                                             |
| ------------------------- | --------- | -------- | ------------------------------------------------------ |
| reconcile errors          | threshold | warning  | rate > 0 for 5m                                        |
| reconcile latency p99     | threshold | warning  | > 10s for 10m                                          |
| reconcile/poll staleness  | absence   | critical | time() − last-tick > 300s, no-data = page              |
| persistent condition      | threshold | critical | Conflict/Unresolved/Drifted/BlastBrakeTripped True 15m |
| ledger failures           | threshold | warning  | rate > 0 for 5m                                        |
| vendor/DNS API failures   | threshold | warning  | rate > 0 for 5m                                        |
| provisioning duration p99 | threshold | warning  | > 300s for 15m                                         |
| webhook compile failures  | threshold | warning  | rate > 0 for 5m                                        |
| materialization/ack lag   | threshold | critical | > 300s for 10m                                         |
| tenant-sync failures      | threshold | warning  | rate > 0 for 5m                                        |

### Gate 6 — Alert-set folders required

- None yet. The default pack ships as the chart's `GrafanaAlertRuleGroup`.
  Add `alerts/{alert-slug}/` only when a Phase 3/4 controller needs a curated,
  runbook-backed alert set beyond the parameterized default.
