# Zinc baseline

zinc is the **pure own-resources cert-manager issuer chart** for AtomiCloud
landscapes. It is a materialized product (S30): it inherits the helm-wrapper
_shape_ — one label prefix, namespace-sourced LPSM identity, and the inherited
rendered-manifest validation stage — but **not** the template's CyanPrint probe
matrix. There is no `probes/`, no `features.json`, and no gate/smoke/presence
probe classes; evidence is an ordinary testing pyramid with negative fixtures as
normal tests (Q-I27).

Unlike sulfur (which vendors the cert-manager engine), zinc vendors **no upstream
chart**. It ships templates only: the Let's Encrypt ACME DNS-01 (Cloudflare)
`ClusterIssuer` set and the `ExternalSecret` for the Cloudflare API token. Several
inherited surfaces are therefore absent: `update`/`latest`, config vendoring, the
Reloader annotation, the pre-sync hook Job, and any workload/image/dependency
gate.

## Engine / issuer split

sulfur owns the cert-manager **engine**; zinc owns the **issuer set**. They stay
separate charts because the engine and the issuer set are independent concerns.
The unit `issuer-cardinality` gate enforces that exactly one template file defines
the issuer, and its negative fixture drops a second hand-authored `ClusterIssuer`
template and confirms the checker reddens.

## Certificate ownership boundary

zinc renders **zero `Certificate` objects**. Registered-fleet platinum retains its
standing wildcard `Certificate` intents; the ENTEI exposure materializer owns one
exact-name `Certificate` per approved dotted hostname (Q-ENV45/Q-ENV47) and selects
one of zinc's issuer refs. A broad per-landscape wildcard is not an ENTEI
substitute because DNS/TLS wildcards cover only one label. The unit
`no-certificate` gate asserts zero Certificates across every overlay; its negative
fixture drops a wildcard `Certificate` template and confirms the count reddens.

## The reusable ClusterIssuer definition

`chart/templates/clusterissuer.yaml` renders **one** DNS-01 ACME definition once
per `issuer.refs` entry. Each entry selects a named LE ACME directory
(`production` or `staging`). `ClusterIssuer` is cluster-scoped, so the definition
is instantiated per cluster; there are no per-landscape/zone issuer variants
beyond the directory selection.

- **LE-directory map (Q-I33, amended)** — production on `pikachu`/`raichu`/
  `amphoros`, staging on `pichu`/`lapras`. The `le-directory-map` gate renders each
  landscape overlay and asserts the rendered `spec.acme.server`; the negative
  points a production-map landscape at the staging directory and confirms the
  server is observably off-map.
- **ENTEI overlay (Q-ENV47)** — `chart/values.entei.yaml` renders the staging and
  production refs concurrently from the one definition, restricted to the
  hosted-development authority zones. The `entei-overlay` gate asserts both refs,
  their ACME directories, and the zone restriction; its negatives drop the zone
  restriction and swap a ref's directory and confirm each reddens.

## Identity, labels, and the Cloudflare token

Platform is always the release namespace (`serviceTree.platform` as a value is
forbidden); the overlays add the landscape slot. The `labels` gate checks the LPSM
projection on the `ClusterIssuer` and `ExternalSecret`, that a namespace change
moves the platform label, that a `labelPrefix` override reprefixes every key with
no `atomi.cloud/*` residue, and that a forbidden platform value is rejected at
render time.

The Cloudflare API token is materialized by the `ExternalSecret` from the platform
SecretStore (folder-prefix rewrites yield `ZINC_CLOUDFLARE_API_TOKEN`) and the
DNS-01 solver references it via `apiTokenSecretRef` only. The `credential-literal`
gate asserts no inline token exists; its negative injects an inline `apiToken`
value and confirms the grep catches it.

## Testing pyramid

The unit/static tier (`scripts/ci/zinc.sh`) runs: Helm schema/lint/render over the
base and every overlay; a schema negative plus the generated-schema drift gate;
the LPSM labels projection; the LE-directory map; issuer cardinality; the ENTEI
overlay; the no-Certificate boundary; the credential-literal boundary; the
inherited Q-G20 rendered-manifest stage (helm template → kubeconform → Kyverno VAP
eval, with the one schema-invalid wiring sabotage — VAP evaluation is vacuous on
this workload-free chart, but render + kubeconform still run); git/OCI packaging
dry-runs and the version==tag mismatch rejection; and required-file presence.

The integration tier (`scripts/validate/zinc-k3d.sh`) creates an ephemeral k3d
cluster, installs the cert-manager and external-secrets CRDs, installs the chart on
the lapras (staging) landscape, asserts the `ClusterIssuer` and `ExternalSecret`
apply, installs the ENTEI overlay and asserts the staging+production pair with the
hosted-zone restriction, confirms zinc owns no `Certificate`, and validates that a
materializer-owned exact-name `Certificate` can reference the zinc rail. Ready
conditions need live Let's Encrypt + Cloudflare credentials and are a Layer C
pre-release step.

## Tokenization

Per-instance/tokenized values are: chart and release names; OCI/git repository;
the namespace-derived platform plus service/module/layer; `labelPrefix`; the
landscape overlay filenames and their LE-directory selection; the ENTEI
hosted-development authority zones; the ACME registration email; the ACME
directory endpoints; the Cloudflare token Secret name/key and the platform
SecretStore name; and the k3d cluster/registry names plus the cert-manager and
external-secrets CRD versions installed at the integration tier.
