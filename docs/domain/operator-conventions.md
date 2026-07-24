# Operator conventions

The reusable operator skeleton restated in family conventions. Every dogfood
consumer (`dependency-operator`/T3, `boron`, `logto-operator`, `error-portal`)
implements these conventions; it does not reinvent them. The toy `Note` and
`Journal` controllers in this template exercise the generic subset end to end.

## Three-layer shape

- The pure `lib/operator` layer (unit tier at 100%) holds desired-state
  computation, the ledger state machine, the blast-brake decision, the
  observe-mode planner, and condition derivation. It imports no Kubernetes
  package (`k8s.io` or `sigs.k8s.io`); the architecture gate enforces this.
- The `adapters/operator` layer (int tier: envtest and testcontainers) holds the
  Kubernetes client/recorder/clock seams (`kube`), the S3/MinIO ledger store
  (`ledgerstore`), and the thin controller-runtime reconcilers (`controllers`).
- One composition root, `cmd/manager`, wires N controllers explicitly with
  per-controller `--enable-<name>` flags and per-controller-scoped config.

## Why marker completeness uses a custom gate

A missing Kubebuilder marker is not a syntax error anywhere in the toolchain: it
silently produces a weaker CRD. The marker-lint spike removed
`+kubebuilder:subresource:status` from `Note` and re-ran the installed tools.

- `controller-gen crd paths=./api/...` exited zero and emitted a complete CRD;
  the only difference was `subresources: {}` where the committed artifact has
  `subresources: {status: {}}`. A weaker schema, not a failure.
- `golangci-lint run ./...` reported zero issues — marker comments are ordinary
  comments to the Go linters.
- `kubeconform` validates a rendered resource against a published JSON schema.
  It has no vocabulary for "this repository requires a status subresource,
  these print columns, these field constraints, and exactly these RBAC grants",
  and in the offline gate it does not even carry a `CustomResourceDefinition`
  schema. It cannot establish marker completeness.

No installed tool covers omission of a valid-but-required marker, so the small
custom gate is necessary. `scripts/validate/operator-markers.sh` extracts each
marker comment block and attaches it to the declaration it precedes, then
asserts a declared policy:

- every served kind (read from the committed CRDs) declares
  `object:root=true`, `subresource:status`, its `resource:` scope/shortName,
  and its required print columns — at that kind, not merely somewhere in the
  file;
- every named spec field carries its required validation constraints, and any
  spec field added later carries at least one `+kubebuilder:validation:` marker;
- every controller declares exactly the expected RBAC grants — a missing grant
  and an unlisted extra grant both redden the gate.

Adding a served kind without a policy line reddens the gate too, so the policy
cannot rot behind new API surface. The `a-operator-markers` hook makes the
decision blocking, and its probe reddens the gate by dropping one required
print column while every other marker family stays intact.

## Lifecycle patterns

- Converge: compute the full desired state each reconcile; apply the diff; never
  assume prior state. A healthy object yields an empty plan.
- Idempotent-once: creating an external record is keyed on a deterministic name
  so a repeat reconcile adopts the existing record rather than duplicating.
- Per-version-intent: a new operator version reports the diff it would apply
  (observe mode) before it is allowed to write (active mode).

## Requeue and backoff

Return an error to get controller-runtime's exponential backoff; return an empty
result for level-triggered re-reconcile on the next watch event. Do not sleep in
a reconcile.

## Condition vocabulary (`metav1.Condition`)

Controllers flip a standard, ArgoCD-Lua-gateable vocabulary derived by the pure
lib: `Ready`, `Drifted`, `Conflict`, `WaitingForEndpoint`, `BlastBrakeTripped`.
Conditions carry `ObservedGeneration`; the transition time comes from the
injected clock so tests are deterministic.

## Finalizer and delete-protection

Every controller that owns external state adds a finalizer. On CR delete the
finalizer runs the cleanup ritual — delete owned in-cluster resources and orphan
the ledger entry — then removes itself. A finalizer never destroys the external
record.

## Deterministic external names — find-or-ADOPT

External resources use a stable, coordinate-derived name. Reconcile is
lookup-first: an existing record is adopted back, never duplicate-created, and a
pre-existing collision is surfaced as a `Conflict` condition rather than a
fail-on-exists error.

## Ledger discipline (the durable R2 ledger)

The source of record lives outside etcd (an S3/MinIO bucket here, R2 in
production). Writes follow intent, then create, then confirm. Recovery is
ledger-lookup-first. A CR delete orphans the entry and never destroys the
external record. `secretPath` on an entry is a pointer, never a secret value.

## Observe to active upgrade ritual

`--observe` (chart `mode: observe`) computes the full desired state read-only and
reports the would-apply plan through conditions, metrics, and logs — never a side
channel. A healthy fleet observed produces an empty plan. Flip to `mode: active`
only after the reported plan is understood. There are exactly two modes.

## Blast-brake rules

A reconcile refuses a destructive batch that would delete more than the
configured percentage-per-tick cap while health passes: it freezes, flips
`BlastBrakeTripped`, emits a warning event, and writes nothing. It never empties
a set while health checks pass.

## Metrics hard DoD (shipped in the chart)

The manager registers generic metrics on the controller-runtime registry and the
chart ships a `ServiceMonitor`, a `GrafanaAlertRuleGroup` (the observability
standard — never a `PrometheusRule`), and a Grafana dashboard.

The toy actually emits: `operator_template_condition` (condition-state gauge by
controller and type), `operator_template_ledger_failures_total`,
`operator_template_reconcile_ticks_total` (poll-loop liveness), and the built-in
`controller_runtime_reconcile_*` reconcile/latency metrics. The dashboard and the
alert group query exactly these.

The consumer taxonomy — provisioning durations, vendor API failures, and the
webhook six-state taxonomy (owned, double-own, no-owner, misroute, dead-letter,
lag) — is shipped as a parameterized metric-name **source** (the
`metric-taxonomy` ConfigMap), which real controllers implement. The toy does not
claim to emit it. A durable-ledger endpoint failure surfaces as the
`WaitingForEndpoint` condition and increments the ledger-failure metric.

The secured metrics endpoint uses controller-runtime's authn/authz filter: the
manager ServiceAccount is granted `create` on TokenReviews and
SubjectAccessReviews, and the chart provisions a least-privilege scraper identity
(ServiceAccount, ClusterRole with `get` on `/metrics`, binding, and token) that
the ServiceMonitor presents — the manager's own token is not authorized to scrape.

## Leader election and rollout

Leader election is on even for a single replica. The operator is stateless —
rollback is an image revert. CRDs ship as ordinary chart templates (not a `crds/`
directory, not a subchart) so `helm upgrade` carries versioned, additive schema
changes.

## Reusable k3d harness

`scripts/local/operator-e2e.sh` provisions a throwaway k3d cluster, builds and
imports the manager image, stands up a MinIO ledger, installs the chart, applies
a toy `Note`, waits for `Ready`, asserts the owned resources, and tears down.
Consumers reuse it by pointing `CHART`, `VALUES`, and `FIXTURE` at their own
CRDs.
