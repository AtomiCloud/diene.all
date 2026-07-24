# Sulfur baseline

sulfur is the **pure passthrough cert-manager engine wrapper chart** for
AtomiCloud landscapes. It is a materialized product (S30): it inherits the
helm-wrapper _shape_ — one label prefix, namespace-sourced LPSM identity,
Reloader opt-in, and rendered-manifest validation — but **not** the template's
CyanPrint probe matrix. There is no `probes/`, no `features.json`, and no
gate/smoke/presence probe classes; evidence is an ordinary testing pyramid with
negative fixtures as normal tests.

It wraps `jetstack/cert-manager` **pinned v1.20.3** to provide the certificate
lifecycle engine (controller + cainjector + webhook).

## Engine / issuer split (pure passthrough)

sulfur owns the cert-manager **engine only**. It adds **no Issuer or
ClusterIssuer** of its own — the issuer set is zinc's separate chart. The engine
and the issuer set are deliberately independent concerns. The unit
`issuer-boundary` gate fails if any wrapper template defines an `Issuer`/
`ClusterIssuer`, and its negative fixture drops such a template into
`chart/templates/` and confirms the checker reddens. Self-signed Issuer +
Certificate objects are created only at the integration tier, as test-time
custom resources in the cluster — never as committed chart templates.

The wrapper carries only minimal upstream overrides, all under the `certManager`
alias: `crds.enabled`/`crds.keep`, `config.enableGatewayAPI`, resource
envelopes, container hardening, Reloader annotations, and the canonical
`fullnameOverride: cert-manager`.

## Identity and labels

sulfur is **L1-generic**: authentication is a Cloudflare API token, not per-cloud
IAM/IRSA, so it defines no landscape/cluster/zone topology — only ordinary LPSM
labels and near-empty generic overlays.

`global.commonLabels` projects the static service-tree labels
(`service`/`module`/`layer`, plus `landscape` from the overlay) onto every
upstream cert-manager resource through cert-manager's supported passthrough. The
namespace-sourced platform label cannot be a static value, so the wrapper-owned
`sulfur-lpsm` ConfigMap carries the **full dynamic LPSM projection**: platform =
release namespace, the landscape/service/module/layer slots, and reversible
physical-instance annotations. `global.serviceTree.platform` is forbidden as a
value; platform always comes from the release namespace. The unit `labels` gate
checks the ConfigMap's full projection, namespace-follows-platform, the
`labelPrefix` override (which reprefixes the ConfigMap and leaves no
`atomi.cloud/*` key on it), commonLabels↔serviceTree consistency, and that all
three engine Deployments carry the static commonLabels.

## Gateway API and the dead feature gate

Gateway API support (Gateway/HTTPRoute TLS for kgateway) is enabled through the
**stable** `certManager.config.enableGatewayAPI: true` config field. The dead
`ExperimentalGatewayAPISupport` feature gate — a no-op since it defaulted true in
v1.15 — is deliberately absent. The `gateway-api` gate asserts the rendered
controller ConfigMap enables it (negative: disabling the flag reddens); the
`dead-flag` gate asserts the dead gate appears in neither values nor rendered
output (negative: injecting it is caught by the same grep).

## CRDs

`certManager.crds.enabled: true` / `crds.keep: true` install the cert-manager
CRDs as Helm-managed objects that survive uninstall, so issued certificates are
not garbage collected. cert-manager applies CRDs through Helm's ordinary object
channel; no separate skipCrds/Server-Side-Apply CRD path is used. The `crds`
gate asserts the six-CRD set renders (negative: `crds.enabled=false` renders no
CRDs, reddening the presence assertion).

## Sequential-minor upgrade policy (Q-G22)

`chart/upgrade-policy.yaml` declares the pinned and previous cert-manager minors.
`scripts/validate/check-sequential-minor.sh` — this chart repo's OWN CI gate —
allows the pinned minor to advance by at most one minor from `previousMinor`; a
version-skip (or downgrade, or major change) reddens. The CRD upgrade path
follows the same rule. The `sequential-minor` gate runs the checker and its
`SEQ_PINNED_MINOR=1.22` version-skip negative, which must red. Nothing is
fleet-side.

## Upstream selection

The vendored dependency is official cert-manager chart `v1.20.3` / app `v1.20.3`,
pinned pure-passthrough from the recorded source archive hash in
`chart/upstream-evidence.yaml`. The official latest is `v1.21.0` (one sequential
minor ahead); it is not adopted because the wrapper advances one minor at a time.
`scripts/local/vendor-cert-manager.sh` verifies the vendored archive is exactly
the recorded upstream source (no patch). `pls latest` checks the official chart
repository and the `quay.io/jetstack` image registry against the evidence.

## Testing pyramid

The non-live unit/static tier (`scripts/ci/sulfur.sh`) includes: Helm
schema/lint/render over base and the landscape+cluster stack; a schema negative
plus the generated-schema drift gate; dependency version/hash verification and
official latest evidence; default/override LPSM projection with namespace-sourced
platform rejection; Reloader default/opt-out on all three engine Deployments;
Gateway API enablement and the dead-flag hygiene gate; the issuer-boundary gate;
the CRD presence gate; the sequential-minor upgrade gate; kubeconform + Kyverno
VAP over every stack (with the `:latest` sabotage); git/OCI packaging dry-runs
and version==tag mismatch rejection; and required-file presence.

The integration tier (`scripts/validate/sulfur-k3d.sh`) creates an ephemeral k3d
cluster, installs the Gateway API CRDs, installs the engine, waits for the
controller/cainjector/webhook Deployments to become Available, and round-trips a
self-signed Issuer + Certificate to `Ready=True` (verifying the issued TLS
Secret).

## Tokenization

Per-instance/tokenized values are: chart and release names; OCI/git repository;
the namespace-derived platform plus service/module/layer; `global.labelPrefix`;
landscape and cluster overlay filenames; the cert-manager chart/app/image
versions, source archive hash, repository, and vendored archive filename; the
sequential-minor policy minors; the Gateway API version installed at the
integration tier; and the k3d cluster/registry names plus the
repository-qualified physical instance id and normalized label.
