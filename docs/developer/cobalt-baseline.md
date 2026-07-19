# Cobalt baseline

This branch is the materialized cobalt product: the External Secrets Operator plus the Infisical source-of-secrets (SoS) `ClusterSecretStore` gateway for AtomiCloud clusters. It instantiates the helm-wrapper shape as a concrete chart instance (S30), so it carries an ordinary testing pyramid, not a CyanPrint probe matrix.

## Purpose

cobalt is the cluster-wide root of the read chain. The `ClusterSecretStore` binds to the SoS Infisical project (tokens only) and is scoped to the cluster's landscape (env == landscape): it can read all SoS tokens for that landscape and nothing else. Downstream carbon (per-cluster chart) pulls its platform's SoS token through this store and creates the platform `SecretStore`; services declare `ExternalSecrets` against that store.

- Pull-only ESO plumbing. There is no `PushSecret` anywhere in diene; cobalt never writes to Infisical.
- The SoS bootstrap credential (the Infisical universal-auth client id/secret) is written into the cluster by the T3 cluster controller during provisioning. cobalt only consumes the bootstrap `Secret`; it never bootstraps the credential itself and never inlines credential literals.
- Infisical runs on Primordial. If Primordial (and Infisical with it) goes down, the consequence is a rotation/sync pause only; already-materialized k8s Secrets persist in-cluster.

## Rendering model

Render values in two independent dimensions (disjoint landscape/cluster vocabularies, never a cross-product):

1. `chart/values.yaml` — service-tree defaults plus the SoS store and minimal ESO overrides.
2. `chart/values.<landscape>.yaml` — landscape identity; pins the store's SoS environment (`environmentSlug`). This is the only per-landscape delta.
3. `chart/values.<cluster>.yaml` — thin cluster identity.

The sample stack is `values.yaml` → `values.example.yaml` → `values.lapras.yaml`. The base chart deliberately fails to render without a landscape overlay: the store MUST be scoped to a landscape.

## Identity and naming

- `labelPrefix` (default `atomi.cloud`) is the only prefix input; every service-tree label/annotation helper reads it.
- LPSM is `{landscape, platform, service, module}`. cobalt is cluster-wide layer-1 infrastructure, so `platform` is a layer-1 scope marker (`cluster`) rather than a release namespace.
- The `ClusterSecretStore` fullname is `cobalt-sos` (`<service>-<token>`, exactly one dash, fused token). The ESO subchart receives `fullnameOverride: cobalt-eso`.

## Secrets

The `ClusterSecretStore` uses the Infisical provider with universal-auth credentials read from the bootstrap `Secret` (`cobalt-sos-bootstrap` in the `external-secrets` namespace). The template refuses any inline credential literal. The store is landscape-scoped: `projectSlug: sos`, `environmentSlug` from the overlay, `secretsPath: /`, `recursive: false`. All resources use `external-secrets.io/v1`; v1beta1 is never authored.

## Absent wrapper surfaces

cobalt inherits the helm-wrapper shape but three sample surfaces are intentionally absent: there is no pre-sync migration hook Job, no build-phase config vendoring, and no ExternalSecret folder-prefix mapping (cobalt authors a `ClusterSecretStore`, not `ExternalSecret`s).

## Rendered-manifest validation

`scripts/validate/cobalt.sh rendered-manifests` runs the generic chart-bearing-repository stage:

1. Helm renders the stacked values.
2. kubeconform validates Kubernetes objects plus the checked-in local `ClusterSecretStore` schema. Upstream ESO CRD definitions are vendored and skipped (`-skip CustomResourceDefinition`); they are validated upstream.
3. Kyverno CLI evaluates definition-only native ValidatingAdmissionPolicy fixtures against the workload and Service resources named by those policies' `resourceRules`.

The local VAP profile covers explicit non-latest tags, requests/limits, non-root baseline-plus security, and the NodePort prohibition. cobalt proves the wiring with one `:latest` fault (`vap-latest-negative`).

## Publishing

OCI is the default publish/consume mode. Git chart repositories remain secondary. `scripts/release/bump.sh` stamps `chart/Chart.yaml` at the release commit. `scripts/ci/publish.sh` refuses a manifest/tag mismatch, regenerates Helm docs, derives the package name from `chart/Chart.yaml`, and supports git packaging plus OCI dry-run or push.

## Tokenization surface

Tokenize these isolated scalars when materializing an instance:

- chart and release name (`diene-cobalt`, `cobalt-sos`, `cobalt-eso`);
- `serviceTree` platform/service/module/layer values;
- `labelPrefix`;
- upstream chart name/version/repository (`external-secrets`, `2.7.0`) and vendored archive filename;
- upstream image reference (`ghcr.io/external-secrets/external-secrets`);
- Infisical `hostAPI`, SoS `projectSlug`, and the bootstrap `Secret` name/namespace;
- OCI organization/repository path and secondary git repository URL;
- landscape and cluster overlay filenames;
- k3d cluster and local registry names.

Held ENV profile names, final landscape rosters, and the exact bootstrap credential interface stay outside this node until their owning work lands.
