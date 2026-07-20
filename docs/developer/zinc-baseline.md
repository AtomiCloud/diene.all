# Zinc baseline

<!-- ### helm-wrapper-instance -->
<!-- #### source: zinc -->

zinc is the AtomiCloud cert-manager **issuer-set** chart. It is a materialized
product (S30) that consumes Sulfur's cert-manager CRDs and controller contract
without copying the engine. The chart wraps nothing upstream and renders only
its own `ClusterIssuer` definitions plus one `ExternalSecret` for the Cloudflare
DNS-01 token.

## Ownership boundary

- **Sulfur** owns cert-manager CRDs, controller, cainjector, and webhook.
- **Zinc** owns reusable ACME DNS-01 `ClusterIssuer` definitions and the ESO
  reference that materializes their Cloudflare token.
- **Platinum** retains registered-fleet wildcard Certificate intents.
- The **ENTEI exposure materializer** owns one exact-name `Certificate` per
  approved dotted hostname and selects Zinc's staging or production ref.

Zinc never renders a `Certificate`. A wildcard such as
`*.eevee.dev.atomi.cloud` cannot cover a dotted hostname such as
`api.zinc.nitroso.kirin.eevee.dev.atomi.cloud`, so no ENTEI wildcard fallback
is accepted.

## Issuer definition and directory map

`templates/_helpers.tpl` contains one reusable `zinc.clusterIssuer` definition.
For registered-fleet installs it is instantiated once in each cluster as
`zinc-acme`. Landscape overlays change only the selected Let's Encrypt
directory:

| Landscape | Directory  |
| --------- | ---------- |
| pichu     | staging    |
| lapras    | staging    |
| pikachu   | production |
| raichu    | production |
| amphoros  | production |

The cluster dimension remains independent and thin (`values.local.yaml` is the
integration fixture). There are no landscape-specific templates or zone-specific
issuer variants.

`values.entei.yaml` is the explicit host-role exception. The same reusable
definition materializes two concurrent, stable issuance-class refs:

- `zinc-staging` → Let's Encrypt staging;
- `zinc-production` → Let's Encrypt production.

Both are restricted to the hosted-development authority:
`eevee.dev.atomi.cloud`, `plusle.dev.atomi.cloud`,
`minun.dev.atomi.cloud`, and `entei.dev.atomi.cloud`. Automated/high-churn
issuance selects staging; trusted interactive exposure selects production.

## Secrets and identity

The one `ExternalSecret`, `zinc-cloudflare`, assumes the platform SecretStore
created by carbon through the SoS chain. It uses `dataFrom.find` against
`/shared/cloudflare/dns01` and the folder-prefix rewrite
`SHARED_$1`; `issuer.cloudflare.apiTokenSecretRef` is the single source for the
issuer and ExternalSecret target, and references only
`zinc-cloudflare/SHARED_API_TOKEN`.
No credential literal or hand-written per-key ESO mapping is allowed.

Every ClusterIssuer and ExternalSecret carries the LPSM projection
`sample/zinc/issuer/1` through the single configurable `labelPrefix`. Landscape
and cluster values arrive from independent overlays. Platform is sourced from
the Helm release namespace and a mismatch fails rendering. Every rendered
resource and account Secret reference follows the exactly-one-dash
`<service>-<token>` convention.

## Rendered-manifest validation

The inherited Q-G20 stage renders the full values stack and validates both
custom resources with checked-in kubeconform schemas. Zinc has no workload
target, so Kyverno's VAP result is intentionally vacuous; the evaluator is still
invoked with the empty matched-resource set. Zinc carries exactly one wiring
sabotage: a rendered ExternalSecret is mutated to a schema-invalid shape and
kubeconform must reject it. Per-rule VAP fixtures remain solely with the VAP
policy chart.

## Testing pyramid

Zinc uses ordinary product tests, never `probes/` or `features.json`:

- **Unit/static** (`scripts/ci/zinc.sh`): schema and drift, lint/render for every
  committed overlay stack, LPSM labels and prefix override, five-landscape
  directory map plus negative fixtures, ENTEI directory/zone/ref negatives,
  issuer cardinality, zero-Certificate ownership, ESO mapping and credential
  guards, Q-G20 validation, Taskfile wiring, k3d safety contract, publish modes,
  version guard, release consistency, and required source presence.
- **Integration** (`scripts/validate/zinc-k3d.sh`): an ownership-isolated k3d
  cluster receives the checksum-pinned cert-manager v1.20.3 CRDs (not the Sulfur
  engine), applies the registered and ENTEI Zinc releases, then applies two
  materializer-owned exact-name Certificate intents referencing the stable
  staging and production rails. Readiness is deliberately not asserted without
  live ACME/Cloudflare. The proof also round-trips the OCI package.

The integration tier is serialized fleet evidence. Local source verification
must not run it or CyanPrint.

## Publishing and tokenization

OCI is the default publication mode and git-as-chart-repo is secondary.
`scripts/ci/publish.sh` verifies chart version equals the release tag, runs
helm-docs, and packages the dependency-free chart.

Tokenization surface: chart/release name (`diene-zinc` / `zinc`) ·
serviceTree platform/service/module/layer · `labelPrefix` · issuer ref and ACME
account Secret names · ACME email/directory · DNS-zone list · platform
SecretStore and ESO folder/target/key names · OCI organization/repository and
git URL · independent landscape and cluster overlay filenames · invocation-owned
k3d cluster/registry names and ports.

## Held boundary

This node intentionally does not add final fleet/Garden profile membership,
landscape-directory entries, hosted profile filters, standalone frontend or
public-callback wiring, or other ENV-owned tails. It supplies only the chart
contract those later owners consume.
