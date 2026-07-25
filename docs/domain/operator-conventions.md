# Operator conventions

The reusable operator skeleton restated in family conventions, materialized as
the **Boron edge-access operator**: three real CRDs (`Account`, `Tunnel`,
`Exposure`) implement the conventions the operator-template proves once.

## Three-layer shape

- The pure `lib/operator` layer (unit tier at 100%) holds every domain
  decision: hostname derivation, install-profile admission, exact-host TLS
  fail-closed ordering, policy resolution, the shared-backend guardrail,
  oldest-wins conflict determinism, and condition derivation. It imports no
  Kubernetes package (`k8s.io` or `sigs.k8s.io`); the architecture gate
  enforces this.
- The `adapters/operator` layer (int tier: envtest) holds the Kubernetes
  client/recorder/clock seams (`kube`), the Cloudflare provider boundary
  (`cloudflare`: a real HTTP adapter plus the in-memory fake used by tests and
  the e2e fake-CF profile), and the thin controller-runtime reconcilers
  (`controllers`).
- One composition root, `cmd/manager`, wires the three controllers explicitly
  with per-controller `--enable-<name>` flags and the trusted installation
  identity (`--install-profile`, `--connected`, `--ditto-inspect`,
  `--landscape`, `--instance`).

## Why marker completeness uses a custom gate

A missing Kubebuilder marker is not a syntax error anywhere in the toolchain: it
silently produces a weaker CRD (`controller-gen` exits zero, the Go linters see
ordinary comments, and `kubeconform` has no vocabulary for "this repository
requires a status subresource and exactly these RBAC grants"). The small custom
gate `scripts/validate/operator-markers.sh` extracts each marker comment block,
attaches it to the declaration it precedes, and asserts a declared policy:

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
decision blocking.

## Lifecycle patterns

- Converge: compute the full desired state each reconcile; apply the diff; never
  assume prior state. A healthy object yields an empty plan.
- Idempotent-once / find-or-ADOPT: creating an external record is keyed on a
  deterministic, coordinate-derived name so a repeat reconcile adopts the
  existing record rather than duplicating. Boron's concrete form is
  **LIST-then-adopt** on Access Applications: reconcile lists for the exact
  derived hostname(+path) first and adopts; CF's duplicate-create 409
  (`access.api.error.application_already_exists`) falls back to the same
  LIST-then-adopt path, never a hard error.

## Requeue and backoff

Return an error to get controller-runtime's exponential backoff; return an empty
result for level-triggered re-reconcile on the next watch event. Do not sleep in
a reconcile.

## Condition vocabulary (`metav1.Condition`)

Controllers flip a standard, ArgoCD-Lua-gateable vocabulary derived by the pure
lib — Account: `TokenValid` · `Ready`; Tunnel: `AccountNotReady` ·
`ConfigSynced` · `ReplicasReady`; Exposure: `Accepted` · `ResolvedRefs` ·
`Programmed` · `Conflicted`. Conditions carry `ObservedGeneration`; the
transition time comes from the injected clock so tests are deterministic.

## Finalizer and delete-protection

Every controller that owns external state adds a finalizer. A Tunnel delete
removes the owned cloudflared Deployment but never destroys the external tunnel
record. An Exposure delete removes its Access Application and proxied CNAME —
exactly the objects it programmed — then removes itself.

## Fail-closed ordering

The Exposure reconcile refuses in a strict order before programming anything:
profile admission → tunnel/account readiness → coordinate trust → path
normalization (`UnsupportedMatch`) → exact-host DNS/edge-TLS preflight
(`UnsupportedTLSCoverage`) → backend + shared-backend guardrail → policy
resolution (`PolicyMissing`, all-or-nothing) → conflict determinism. ANY
refusal programs NOTHING: no DNS record, no Access Application, no tunnel rule,
and any previously held route is released.

## Metrics hard DoD (shipped in the chart)

The manager registers generic metrics on the controller-runtime registry and the
chart ships a `ServiceMonitor`, a `GrafanaAlertRuleGroup` (the observability
standard — never a `PrometheusRule`), and a Grafana dashboard.

Boron emits: `boron_condition` (condition-state gauge by controller and type),
`boron_provider_failures_total` (Cloudflare API operation failures), and
`boron_reconcile_ticks_total` (poll-loop liveness), alongside the built-in
`controller_runtime_reconcile_*` reconcile/latency metrics. The dashboard and
the alert group query exactly these; the `metric-taxonomy` ConfigMap records
the emitted set.

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

## k3d e2e harness

`scripts/local/operator-e2e.sh` provisions a throwaway k3d cluster, builds and
imports the nonroot manager image, installs the chart in the connected-lapras
profile with the fake-CF adapter, applies the Account/Tunnel/Exposure chain,
waits for `Programmed`, asserts the derived hostname, the fixed 2 cloudflared
replicas, the tunnel route, and the unauthenticated-refusal (`PolicyMissing`)
case, and tears down.
