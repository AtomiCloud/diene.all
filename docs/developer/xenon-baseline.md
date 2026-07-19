# Xenon baseline

xenon is the **conditional metrics-server wrapper chart** for AtomiCloud platform
landscapes. It is a materialized product (S30) and an **edge chart** (Q-I32): it
inherits the helm-wrapper _shape_ — configurable `labelPrefix`, LPSM labels, the
exact-one-dash fullname convention, Reloader opt-in, and the rendered-manifest
validation stage — but **not** the helm-wrapper probe obligation or its service-
template surfaces. There is no `probes/`, no `features.json`, and no probe matrix.

It wraps upstream `kubernetes-sigs/metrics-server` to provide the resource metrics
API used by HPA and `kubectl top`. Three inherited helm-wrapper surfaces are
**absent** here: the pre-sync hook Job (no db-init/migration), build-phase config
vendoring (no external config), and ES folder-prefix mapping (no ExternalSecrets).

## Conditional enablement

The whole chart is gated by a single value, `metricsServer.enabled`. The
**per-landscape toggle is the real surface** of this chart:

- **ON** for every cloud and on-prem landscape — EKS classic, EKS Auto Mode,
  DOKS, and on-prem. Verified from the managed-offering docs: none of these
  preinstall metrics-server (EKS clusters are T3/API-created and get nothing;
  DOKS offers it only as a Marketplace 1-click, user-managed; EKS Auto Mode
  built-ins do not include it).
- **OFF** only on k3d/lapras, because k3s bundles metrics-server (disable it via
  `--disable metrics-server`).

When OFF the chart renders **no resources** and remains installable everywhere —
it is never fully dropped. The final per-profile ENV roster (the seven Garden
profiles and their posture matrices) is intentionally excluded from this node and
stays owned by the ENV round.

### Toggle map

`chart/toggle-map.yaml` is the source of truth for the unit-tier toggle gate. It
declares, per committed overlay, the expected enablement. The gate renders
`values.yaml` stacked with each overlay and asserts the ACTUAL enablement
(resources render = on; empty render = off) matches the declared value. A
negative fixture flips the lapras overlay from OFF to ON and confirms the
baseline still declares OFF, so the gate reddens on a regression that accidentally
enables xenon on k3d.

### Per-cloud needed/provided matrix

| Cloud         | metrics-server preinstalled? | xenon enabled | kubelet TLS                            |
| ------------- | ---------------------------- | ------------- | -------------------------------------- |
| EKS classic   | no                           | ON            | secure                                 |
| EKS Auto Mode | no                           | ON            | secure                                 |
| DOKS          | no                           | ON            | secure                                 |
| on-prem       | no                           | ON            | overlay (per-cluster kubelet TLS args) |
| k3d / lapras  | yes (k3s bundles it)         | OFF           | bundled                                |

Secure kubelet TLS is the cloud/on-prem default; the k3d/insecure posture
(`--kubelet-insecure-tls`) is an overlay decision, never a baseline default.

## Rendering model

Two independent stacked dimensions, inherited from helm-wrapper: base
`values.yaml` → landscape overlay `values.<landscape>.yaml` → cluster overlay
`values.<cluster>.yaml`. Landscape and cluster name vocabularies are disjoint, so
flat filenames are unambiguous. The shipped overlays are:

- `values.example.yaml` — a representative managed-cloud landscape (ON).
- `values.lapras.yaml` — the local k3d cluster overlay; it contains no landscape
  decision and disables xenon (OFF).

`metricsServer.enabled` is read by the metrics-server subchart's `condition`, so
toggling it off drops the entire subchart. The wrapper-owned LPSM projection
ConfigMap is also gated by the same value, so an OFF landscape renders nothing.

## Identity and naming

- `serviceTree`: platform `sample`, service `xenon`, module `metrics`, layer `1`.
  Landscape and cluster are added by overlays only.
- `labelPrefix` (default `atomi.cloud`) is the single configurable prefix read by
  every `_helpers.tpl` label/annotation helper; it is never hard-coded.
- **Fullname convention** (`<service>-<dashless-token>`, exactly one dash): the
  metrics-server workload and the LPSM ConfigMap are stamped via
  `metricsServer.fullnameOverride` (`xenon-metrics`) and the
  `xenon.resourceName` helper (`xenon-lpsm`). Upstream metrics-server RBAC and
  APIService objects keep their own conventional names (e.g.
  `system:auth-delegator`, `v1beta1.metrics.k8s.io`); the fullname convention
  scopes to the controllable workload and wrapper-owned names.

## Workloads

- The metrics-server Deployment carries service-tree `podLabels` and
  `podAnnotations` from `metricsServer.podLabels`/`podAnnotations`, so the
  LPSM identity reaches the pod even though the subchart owns the template.
- **Reloader opt-in** is baked ON by default via
  `metricsServer.podAnnotations."reloader.stakater.com/auto": "true"`. The
  annotation reaches the pod through the metrics-server subchart's `podAnnotations`
  map; Helm coalesces subchart values and cannot drop a single key, so a
  stateful/unsafe landscape opts out by overriding the value to `"false"`
  (Reloader only reloads on the literal `"true"`). metrics-server is itself
  stateless; the opt-out path is proven for the shape, not because metrics-server
  needs it.
- Pod and container security contexts satisfy the baseline-plus VAP policy
  (non-root, dropped capabilities, read-only root filesystem, resource
  requests+limits, no `:latest` image, ClusterIP Service).

## Rendered-manifest validation

The generic rendered-manifest validation stage (Q-G20), defined once in
helm-wrapper, is inherited as machinery: `helm template` (all stacked values) →
`kubeconform` (k8s schemas) → VAP eval via `kyverno apply` against
`policies/vap` (ValidatingAdmissionPolicy definitions only). The metrics-server
Deployment and Service pass; **one wiring sabotage** (`metricsServer.image.tag=latest`)
reddens the stage, proving the VAP wiring cannot silently stop matching.

## Publishing

OCI is the default publish/consume path; git-as-chart-repo is the secondary mode.
`scripts/ci/publish.sh` stamps the Chart.yaml version via the release tag
(version==tag guard) and runs helm-docs. Both modes are exercised as dry-runs in
the unit tier; the package is `diene-xenon-<version>.tgz`.

## Testing pyramid

xenon is a materialized product (S30) and edge chart (Q-I32) — it uses an ordinary
testing pyramid, **not** a CyanPrint probe matrix.

- **Unit tier (static conformance):** helm lint per overlay; `values.schema.json`
  validation + drift; LPSM label conformance + prefix override; Reloader
  opt-out; fullname convention; toggle-map gate + negative fixture; rendered-
  manifest validation (Q-G20, one `:latest` wiring sabotage); cluster Taskfile
  include consistency; release-config consistency; CI wiring; publish version==tag.
- **Integration / SIT tier:** install xenon on a landscape where it is enabled,
  then verify `kubectl top nodes` answers. xenon is OFF on k3d/lapras, so there
  is no local k3d probe stand-in; the SIT proof runs where the chart is actually
  on (a cloud/on-prem landscape), under orchestration authorization.

## Tokenization surface

Every per-instance scalar, enumerated:

- chart/release name (fullname `<service>-<token>` = `xenon-metrics`, one dash)
- chart publish name (`diene-xenon`) and OCI/git repository path
- serviceTree platform/service/module/layer (`sample`/`xenon`/`metrics`/`1`)
- `labelPrefix` value (`atomi.cloud`)
- upstream dependency name + version + repository (`metrics-server` 3.12.1,
  `https://kubernetes-sigs.github.io/metrics-server`)
- vendored tgz filename (`charts/metrics-server-3.12.1.tgz`)
- skopeo image ref in `latest` (`registry.k8s.io/metrics-server/metrics-server`)
- landscape overlay filenames (`values.<landscape>.yaml`)
- cluster overlay filenames (`values.<cluster>.yaml`)
- k3d cluster name (`diene-xenon`) and registry name (`diene-xenon-registry`)
- repository-qualified physical instance id and its normalized DNS-1123 label
  (with the original recorded together in metadata for reversible shortening)
- the per-landscape `enabled` toggle and the kubelet-TLS posture
