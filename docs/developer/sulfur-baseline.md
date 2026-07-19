# Sulfur baseline

<!-- ### helm-wrapper-instance -->
<!-- #### source: sulfur -->

sulfur is the AtomiCloud **cert-manager engine** chart — a materialized product
(S30) that instantiates the helm-wrapper _shape_ without the probe obligation. It
wraps the upstream `jetstack/cert-manager` chart and owns the certificate
lifecycle controller only.

## Rendering model

sulfur is a **pure passthrough**. The upstream chart is declared as a single
dependency and aliased as `upstream`:

```yaml
dependencies:
  - name: cert-manager
    alias: upstream
    version: v1.20.3
    repository: https://charts.jetstack.io
    condition: upstream.enabled
```

sulfur ships **no workload, Service, Issuer, or ClusterIssuer templates of its
own** — `_helpers.tpl` carries identity/validation helpers, and
`templates/validate.yaml` is a **zero-resource** render-time guard that emits no
Kubernetes object (it only invokes `sulfur.validateServiceTree`). Every rendered
resource comes from the cert-manager subchart (controller, cainjector, webhook,
startupapicheck, CRDs). The vendored `charts/cert-manager-v1.20.3.tgz` is the
reproducible source of truth; `helm package` is self-contained without a
dependency rebuild.

## Engine and issuer split

Engine ownership and issuer ownership are deliberately split across two charts
because they are independent concerns:

- **sulfur** owns the cert-manager **engine** (controller + cainjector + webhook).
- **zinc** owns the issuer set (the LE DNS-01 `ClusterIssuer`, one wildcard
  definition per cluster).

sulfur therefore ships **no** `Issuer` or `ClusterIssuer` template (instance);
only the upstream CRD _definitions_ render. The no-issuer boundary is a stated
invariant enforced by the unit tier.

## Identity and naming

- Chart/package name: `diene-sulfur` (repo-qualified `diene-` prefix, matching the
  helm-wrapper template).
- `serviceTree`: `service: sulfur`, `module: certs`, `layer: 1`, `platform:
sample` (the install namespace). Landscape and cluster are added by independent
  overlays.
- LPSM identity labels are stamped onto every rendered resource via
  `upstream.global.commonLabels` (`<prefix>/service|module|layer|platform`,
  `<prefix>/landscape|cluster`). Because subchart values cannot call templates,
  the `commonLabels` keys are **generated** from the single `labelPrefix` (default
  `atomi.cloud`) plus `serviceTree` by `scripts/local/gen-identity-values.sh`.
  That generated layer is the supported, **mandatory** render path: every
  `helm template`/`helm install` appends it, and the zero-resource
  `templates/validate.yaml` guard fails rendering when the layer is absent or its
  platform key does not mirror `serviceTree.platform`. `labelPrefix` is therefore
  the only source of the prefix — overriding it re-keys the rendered labels
  (proven in the unit tier); there is no static, independently editable mirror.
- Platform is **namespace-sourced**: `templates/validate.yaml` invokes
  `sulfur.validateServiceTree`, which fails rendering unless `serviceTree.platform`
  equals the release namespace. The unit tier renders a mismatched namespace as a
  negative fixture.

## Gateway API

Gateway API support is **required** (kgateway integration). The canonical knob is
`upstream.config.enableGatewayAPI`; `config.enableGatewayAPI` is a sulfur-level
static mirror. Both must be `true`. The dead `ExperimentalGatewayAPISupport`
feature gate (removed in cert-manager v1.15) must never appear.

## Sequential-minor upgrades

cert-manager is pinned on a **sequential-minor** upgrade ladder from the fleet
baseline v1.15 — a version bump may advance at most one minor at a time, and
never change the major. The CRD upgrade path rides the same ladder because the
CRDs ship inside the chart. This is enforced by the chart repo's **own CI**
(`scripts/validate/sequential-minor.sh`, Q-G22): a version-bump PR that skips a
minor goes red; nothing fleet-side. The CI entrypoint runs
`sequential-minor.sh --ci-gate chart` (wired into `scripts/ci/sulfur.sh`), which
derives the previous cert-manager pin from the change's base revision (PR base,
push before-SHA, or `HEAD~1` locally) and gates the actual chart-dependency bump.
It **fails** when the comparison source is unavailable rather than degrading to a
lax semver check, so a minor-skipping bump can never merge green.

## CRD lifecycle

CRDs are installed by the engine chart (`upstream.crds.enabled: true`) and kept on
uninstall (`upstream.crds.keep: true`) so certificates survive a chart removal.

## Workload hardening

The inherited workload-baseline VAP (no `:latest`, requests+limits, non-root,
read-only root FS, drop ALL) applies because sulfur renders workloads. cert-manager
defaults already supply the security-context rules; sulfur adds per-component
`resources` (requests+limits) and `containerSecurityContext.runAsNonRoot: true`
so every workload satisfies the baseline.

Reloader is opted **in** by the `reloader.stakater.com/auto: "true"` annotation
baked onto each long-running workload's `upstream.<component>.podAnnotations`
(controller/webhook/cainjector; the one-shot startupapicheck Job is excluded).
The supported opt-out is setting those three nullable annotation values to `null`
from a landscape/cluster overlay — proven in the unit tier. There is no inert
`reloader.enabled` toggle.

## Rendered-manifest validation

The generic Q-G20 stage is inherited from helm-wrapper:
`helm template → kubeconform (k8s schemas; the six cert-manager CRD definitions
are upstream-authoritative and skipped) → kyverno apply VAP eval`. One wiring
sabotage per repo (a `:latest` workload image) proves the stage cannot silently
stop matching.

## Testing pyramid

sulfur is an S30 product: evidence is an **ordinary testing pyramid**, not a
CyanPrint probe matrix.

- **Unit tier** (`scripts/validate/sulfur.sh`, run via `scripts/ci/sulfur.sh`):
  lint, render, schema + drift, LPSM labels + labelPrefix-override render proof,
  the namespace/platform identity guard (positive + mismatched-namespace and
  missing-identity-layer negatives), Reloader opt-out (nullable annotations), the
  Q-G20 rendered-manifest stage, the Q-G22 sequential-minor gate (positive/negative
  fixtures plus the base-derived `--ci-gate` proof), and the contract negative
  fixtures (Gateway API enabled, no dead feature gate, no own Issuer, CRDs
  enabled).
- **Integration tier** (`scripts/validate/sulfur-k3d.sh`): k3d install, the three
  cert-manager Deployments reach Available, and a self-signed Issuer + Certificate
  round-trips to `Ready=True`. Reserved for the orchestrated proof window.

ListenerSet (alpha) is gated by `enableGatewayAPIListenerSet` +
`featureGates.ListenerSets` and is intentionally **not** tested until the feature
is enabled (no dormant checks).

## Publishing

OCI is the default publish mode; git-as-chart-repo is the secondary mode. Both are
exercised as dry-runs in the unit tier. `scripts/ci/publish.sh` stamps the chart
version via yq and verifies `manifest == tag`; the cert-manager dependency is
vendored, so the package builds offline.

## Tokenization surface

Tokenize these isolated scalars when materializing an instance:

- chart and release name (`diene-sulfur` / release `sulfur`);
- `serviceTree` platform/service/module/layer values;
- `labelPrefix` (mirrored into `upstream.global.commonLabels` keys);
- upstream chart name/version/repository and vendored archive filename
  (`cert-manager`, `v1.20.3`, `https://charts.jetstack.io`,
  `cert-manager-v1.20.3.tgz`);
- upstream image references used by `latest` (`quay.io/jetstack/cert-manager-*`);
- OCI organization/repository path and secondary git repository URL;
- landscape and cluster overlay filenames (`values.<landscape>.yaml`,
  `values.<cluster>.yaml`);
- k3d cluster and local registry names;
- the cert-manager version pin (sequential-minor gated).

Held ENV profile names, final Garden membership, ENTEI tails, and the zinc issuer
topology are not tokenized here because this node does not own those decisions.
