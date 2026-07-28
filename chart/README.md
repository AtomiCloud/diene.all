# diene-zinc

![Version: 0.1.0](https://img.shields.io/badge/Version-0.1.0-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square) ![AppVersion: 0.1.0](https://img.shields.io/badge/AppVersion-0.1.0-informational?style=flat-square)

Pure own-resources cert-manager issuer chart (Let's Encrypt ACME DNS-01 ClusterIssuers over Cloudflare) for AtomiCloud platform landscapes

## What zinc owns (and does not)

zinc is a **pure own-resources** chart — templates only, no vendored upstream. It
owns the Let's Encrypt ACME **DNS-01 (Cloudflare)** `ClusterIssuer` set plus the
`ExternalSecret` that materializes the Cloudflare API token from the platform
SecretStore created by carbon via the SoS chain.

zinc owns **no `Certificate`**. Registered-fleet wildcard intents stay on the
registered-fleet platinum rail; on ENTEI, the exposure materializer owns one
exact-name `Certificate` per approved dotted Garden hostname and selects one of
zinc's issuer refs. cert-manager itself (the engine) is
[sulfur](https://github.com/AtomiCloud)'s separate chart — the engine and the
issuer set are deliberately independent concerns.

## Issuer definition and the LE-directory map

One reusable DNS-01 `ClusterIssuer` definition is rendered once per `issuer.refs`
entry. `ClusterIssuer` is cluster-scoped, so it is instantiated per cluster; there
are no per-landscape/zone issuer variants beyond the LE-directory selection the
overlays carry (Q-I33):

- **LE production** directory on `pikachu`, `raichu`, `amphoros`.
- **LE staging** directory on `pichu`, `lapras` (rate-limit protection; the
  staging root installs locally where trust is needed).

The **ENTEI** host-role overlay renders the same definition twice — a staging ref
and a production ref — restricted to the hosted-development DNS authority zones, so
hosted instances can select the issuance class they need (CI selects staging;
trusted interactive exposure selects production). This is an issuance-class split
on one shared host, not a per-landscape wildcard or a new workload landscape
(Q-ENV47).

## Identity and labels

Every owned resource carries the LPSM projection through the wrapper helpers:
platform is the release namespace (never a value), plus the
service/module/layer/landscape slots and reversible physical-instance annotations.
The Cloudflare token is referenced from the ExternalSecret-materialized Secret
only; it is never inlined.

## Requirements

Kubernetes: `>=1.22.0-0`

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| instance | object | `{"physicalId":"example-repository:run-001"}` | Optional physical-instance metadata. The instance remains outside LPSM. |
| instance.physicalId | string | `"example-repository:run-001"` | Repository-qualified physical instance id. |
| issuer | object | `{"acme":{"directories":{"production":"https://acme-v02.api.letsencrypt.org/directory","staging":"https://acme-staging-v02.api.letsencrypt.org/directory"}},"email":"platform@atomi.cloud","refs":[{"directory":"staging","name":"zinc-letsencrypt"}],"solver":{"cloudflare":{"apiTokenSecretRef":{"key":"ZINC_CLOUDFLARE_API_TOKEN","name":"zinc"}},"dnsZones":[]}}` | The reusable Let's Encrypt ACME DNS-01 (Cloudflare) ClusterIssuer definition. Zinc owns NO Certificate: certificate owners reference a stable ClusterIssuer name. ONE definition is rendered once per `refs` entry (cluster-scoped, so it is instantiated per cluster); there are no per-landscape/zone issuer variants beyond the LE-directory selection carried by the overlays. |
| issuer.acme.directories | object | `{"production":"https://acme-v02.api.letsencrypt.org/directory","staging":"https://acme-staging-v02.api.letsencrypt.org/directory"}` | Named Let's Encrypt ACME directory endpoints. A `refs` entry selects one by name; the five-landscape LE-directory map (Q-I33) is expressed by the landscape overlays choosing production or staging. |
| issuer.email | string | `"platform@atomi.cloud"` | ACME registration contact address. |
| issuer.refs | list | `[{"directory":"staging","name":"zinc-letsencrypt"}]` | ClusterIssuer instances to materialize from the one definition. Registered clusters instantiate a single stable ref; the ENTEI host-role overlay instantiates the staging+production pair concurrently on the shared host. |
| issuer.solver.cloudflare.apiTokenSecretRef.key | string | `"ZINC_CLOUDFLARE_API_TOKEN"` | Key inside that Secret (folder-prefixed by the ExternalSecret rewrite). |
| issuer.solver.cloudflare.apiTokenSecretRef.name | string | `"zinc"` | The ExternalSecret-materialized Secret carrying the Cloudflare token. |
| issuer.solver.dnsZones | list | `[]` | DNS-01 solver zone restriction. Empty = unrestricted (registered fleet); the ENTEI overlay pins the hosted-development authority zones. |
| labelPrefix | string | `"atomi.cloud"` | Prefix used by every service-tree label and annotation helper. |
| secret | object | `{"enabled":true,"refreshInterval":"1h","serviceFolder":"/zinc","sharedFolder":"/shared","store":{"kind":"SecretStore","name":"platform-store"}}` | One service-scoped ExternalSecret that materializes the Cloudflare API token from the platform SecretStore created by carbon via the SoS chain. The DNS-01 solver references this Secret only; a token is never inlined. |
| secret.enabled | bool | `true` | Render the ExternalSecret. |
| secret.refreshInterval | string | `"1h"` | ESO refresh cadence. |
| secret.serviceFolder | string | `"/zinc"` | Service-folder path fanned in with a ZINC_ prefix (holds the CF token). |
| secret.sharedFolder | string | `"/shared"` | Shared-folder path fanned in with a SHARED_ prefix. |
| secret.store.kind | string | `"SecretStore"` | The platform SecretStore is namespace-scoped (created by carbon). |
| secret.store.name | string | `"platform-store"` | Platform SecretStore name. |
| serviceTree | object | `{"layer":"1","module":"issuer","service":"zinc"}` | Stable service-tree projection. Platform is always the release namespace (never a value); landscape is added by independent overlays. |
| serviceTree.layer | string | `"1"` | Architecture layer. |
| serviceTree.module | string | `"issuer"` | Module name. |
| serviceTree.service | string | `"zinc"` | Service name. |
