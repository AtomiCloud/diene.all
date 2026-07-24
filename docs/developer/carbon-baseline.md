# Carbon platform baseline

Carbon materializes one platform boundary without owning service deployments. Its
application chart creates the platform namespace, pulls that platform's Universal
Auth pair from Cobalt's landscape-scoped source-of-secrets `ClusterSecretStore`, and
creates the namespaced Infisical `SecretStore` used by platform services. Its
primordial chart creates only platform-shared `PlatformDependency` resources.

## Ownership and identity

- A real deployment namespace is the platform name. A Garden branch overrides only
  the runtime namespace; service-tree platform identity remains stable.
- The application chart owns `Namespace`, `ExternalSecret`, and `SecretStore`.
- The primordial chart owns only `PlatformDependency` and renders exactly one writer
  for each platform and virtual-landscape pair. Duplicate writers fail rendering with
  a `Conflict` diagnostic.
- `PlatformDependency` uses the frozen `fleet.atomi.cloud/v1alpha1` API and carries
  both `spec.landscape` and `spec.placement.preferredHost`.
- Neither chart owns Argo CD applications, vclusters, workloads, service-specific
  version pins, or dependency-operator infrastructure.

## Secret flow

The token `ExternalSecret` is pull-only and uses `dataFrom.extract` so the folder is
the address. It reads `/platforms/<platform>` from `cobalt-sos`; individual secret
keys are never mapped in chart source. The resulting namespace-local Secret supplies
Universal Auth to the platform `SecretStore`, whose Infisical project is the platform
and whose environment is the landscape. No credentials or push path are authored.

## Scaffold and topology

The Cyan entry point asks exactly one question: the platform name. It does not query
landscapes or expose an override. `platform.yaml` is schema-validated and defaults to
landscapes `pichu`, `pikachu`, `raichu`, and `amphoros`, staged sequentially as
`pichu`, `pikachu`, then the parallel group `[raichu, amphoros]`. Belt assignment is
derived downstream and therefore is not declared in this contract.

## Verification boundaries

`scripts/ci/carbon.sh` runs the host-safe tier: Helm schema/lint/render, strict
kubeconform, Kyverno policy wiring and sabotage, platform-schema and scaffold drift,
namespace/folder/dependency negative cases, independent workflow source/filter/name/
concurrency validators, and both publication dry-run modes.

`scripts/validate/carbon-k3d.sh` is a bounded integration harness with path-derived
resource names and ownership-checked teardown. It is reserved for separately
authorized live proof and is never run by the host-safe CI entry point.
