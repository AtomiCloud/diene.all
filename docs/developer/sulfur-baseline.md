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
own** — `_helpers.tpl` carries identity/validation helpers only. Every rendered
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
  `labelPrefix` (default `atomi.cloud`) is **statically mirrored** into the
  `commonLabels` keys; the unit tier proves the mirror stays in sync with the one
  configurable `labelPrefix` (drift invariant).

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
minor goes red; nothing fleet-side.

## CRD lifecycle

CRDs are installed by the engine chart (`upstream.crds.enabled: true`) and kept on
uninstall (`upstream.crds.keep: true`) so certificates survive a chart removal.

## Workload hardening

The inherited workload-baseline VAP (no `:latest`, requests+limits, non-root,
read-only root FS, drop ALL) applies because sulfur renders workloads. cert-manager
defaults already supply the security-context rules; sulfur adds per-component
`resources` (requests+limits) and `containerSecurityContext.runAsNonRoot: true`
so every workload satisfies the baseline.

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
  lint, render, schema + drift, LPSM labels + drift, Reloader opt-out, the Q-G20
  rendered-manifest stage, the Q-G22 sequential-minor gate, and the contract
  negative fixtures (Gateway API enabled, no dead feature gate, no own Issuer,
  CRDs enabled).
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
