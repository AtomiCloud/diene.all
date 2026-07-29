# dotnet-api-primordial

![Version: 0.0.0](https://img.shields.io/badge/Version-0.0.0-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square) ![AppVersion: 0.0.0](https://img.shields.io/badge/AppVersion-0.0.0-informational?style=flat-square)

Primordial chart for the diene .NET API — the T3 CR set (PlatformDependency, Problem catalog, LogtoApp) plus this service's Grafana Operator folder, dashboards, and alerts

## What this chart owns

This is the **primordial chart** half of the two-chart model (R20). It is deployed to the
Primordial cluster; locally both charts land in one cluster.

| Resource                       | Rendered when                                    |
| ------------------------------ | ------------------------------------------------ |
| `PlatformDependency`           | always — one union-set CR per landscape          |
| `Problem`                      | the exported catalog file exists                 |
| `LogtoApp`                     | this chart is the app's placement owner (it is)  |
| `GrafanaFolder`                | always                                           |
| `GrafanaDashboard`             | one per `observability/dashboards/*.json`        |
| `GrafanaAlertRuleGroup`        | one per `observability/alerts/{slug}/{sev}.yaml` |
| `CloudflareDeploy`             | edge assets ship — they do not here              |
| `VirtualLandscapeService`      | this row serves a v-landscape — it does not      |

There is **no Kargo configuration here at all**: Kargo is centralized on Primordial and out of
scope for this repository.

## One union CR, not four

`PlatformDependency` spans the `database` / `kv` / `cache` / `store` modules this service
needs. It **replaces** the old per-kind postgres/redis/S3 CRs, and the redis-streams transport
rides the kv/cache module rather than getting a CR of its own.

Each module block is a **map of named connections**, matching `App/Config/settings.yaml` —
a second pool is data, never code. Dependencies are requested through CRs in **every**
landscape: the operator realizes CNPG/Dragonfly/MinIO in-cluster locally and the managed
classes from Primordial. There is no local-subchart-vs-cloud-CR toggle.

The chart enforces ONE writer per landscape: a duplicate landscape is a loud render-time
`Conflict`, never a silent last-write-wins.

## The Problem catalog, and the landscape rewrite

`problems/catalog-v1.json` is the **committed** output of `pls problems:export`. Each entry's
`type` is the fully minted RFC 9457 URI as of export time; this chart never reconstructs one
from parts.

The exporter mints those URIs from the app's own config, so the committed catalog is stamped
with whichever landscape was configured when it ran. A primordial chart is installed **per
landscape**, so materializing that file verbatim into a `raichu` row would publish a row whose
every `type` URI points at the lapras error portal — wrong data that no lint would catch. The
template therefore substitutes exactly one path triple,
`/<exportLandscape>/<platform>/<service>/` → `/<chartLandscape>/<platform>/<service>/`, and
**fails** on any entry whose `type` does not contain the triple it claims to, so the
substitution can never silently no-op. When a rewrite happens the rendered CR is annotated
with the landscape it was exported for.

The clean long-term fix belongs to `problems:export` — emit landscape-neutral URIs, or one
file per landscape — and is reported upward rather than papered over here.

A missing catalog file renders nothing (a fresh checkout may not have exported yet). A file
that exists but is malformed, empty, stale, or names a different platform/service is a **hard
failure**: "no output" is never allowed to read as "validated".

## Grafana resources

The repository root `observability/` is authoritative. Helm cannot read outside the chart
directory, so `pls helm:vendor` copies it into the gitignored `files/observability/` before
lint, render, package, or publish.

Mappings are mechanical and deterministic:

- service identity → one `GrafanaFolder`, uid `<platform>-<service>-folder`
- `dashboards/{purpose}.json` → one `GrafanaDashboard`, uid `<platform>-<service>-<purpose>`
- `alerts/{slug}/{severity}.yaml` → one `GrafanaAlertRuleGroup` holding exactly one rule

The filename **is** the severity, so severity and emoji cannot disagree. LPSM labels are
injected by the renderer, never hand-authored in the source files. The six-gate method
legitimately yields ZERO dashboards and ZERO alerts, so every template renders cleanly with
none present — no placeholder is ever added just to populate a directory. A file that exists
but violates the contract fails the render.

## Identity is explicit, never inferred

`LogtoApp.spec.identityRef` is `{platform, vlandscape}` and the platform is **required and
explicit**: the operator rejects an omitted platform and a namespace/platform mismatch rather
than inferring one from the CR's namespace. The Logto endpoint is derived from that pair.

Redirect URIs are **derived** by the operator from the live serve-set, so this chart declares
**paths** only; every non-HTTPS / local / vendor exception is explicit through the `extra*`
lists and nothing branches on environment. The service is a confidential machine-to-machine
client with no browser flow, so both declared paths are empty.

## Values overlays

Landscape is the ONLY axis (R16). The base `values.yaml` is a complete **local** release, so a
forgotten overlay degrades to in-cluster classes rather than declaring managed cloud resources
by accident. `castform` (preview) deliberately keeps the local classes: a preview proves
behavior, not capacity, and pointing throwaway environments at managed projects would spend
real money and orphan resources on every closed PR.

`values.schema.json` (R17) validates the base values and every overlay, including the rule
that `delivery: external` requires a `providerAccountRef` and local/replicated modules must
not name one.

## Requirements

Kubernetes: `>=1.27.0-0`

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| cloudflareDeploy | object | `{"apiVersion":"fleet.atomi.cloud/v1alpha1","enabled":false,"pin":true,"scriptName":"","tag":""}` | Cloudflare edge deployment. This service ships NO edge assets — it is an origin API behind the platform gateway — so the surface exists but is gated OFF. A consumer that does ship a Worker only flips `enabled` and names its script. |
| cloudflareDeploy.apiVersion | string | `"fleet.atomi.cloud/v1alpha1"` | API group/version of the CloudflareDeploy CRD. |
| cloudflareDeploy.enabled | bool | `false` | Render the CloudflareDeploy CR. OFF: no edge assets ship from this repository. |
| cloudflareDeploy.pin | bool | `true` | Whether the deployed version is pinned rather than tracking the tag. |
| cloudflareDeploy.scriptName | string | `""` | Worker script name. Required once enabled. |
| cloudflareDeploy.tag | string | `""` | Tag the desired version is read from. |
| dependencyApiVersion | string | `"fleet.atomi.cloud/v1alpha1"` | API group/version of the dependency-operator CRs. |
| labelPrefix | string | `"atomi.cloud"` | Prefix used by every service-tree label and annotation helper. One configurable key (R16/B26) — never hard-coded inside a helper. |
| logtoApp | object | `{"apiVersion":"fleet.atomi.cloud/v1alpha1","enabled":true,"extraCorsOrigins":[],"extraPostLogoutRedirectUris":[],"extraRedirectUris":[],"paths":{"postLogoutPath":"","redirectPath":""},"resourceRefs":[],"type":"MachineToMachine","vlandscape":"mew"}` | One vlandscape-targeted LogtoApp for this app. This chart IS the selected placement owner — it is the only primordial chart for this service and the service declares its own serve-set — so it is ON.  The app is a confidential machine-to-machine client: it mints and validates machine tokens and calls the Logto Management API for onboarding and session revocation. It has no browser login of its own, so both declared paths are empty. Redirect, post-logout, and CORS values are DERIVED by the operator from the live serve-set — a chart declares PATHS, never per-row URIs. |
| logtoApp.apiVersion | string | `"fleet.atomi.cloud/v1alpha1"` | API group/version of the LogtoApp CRD. |
| logtoApp.enabled | bool | `true` | Render the LogtoApp CR. |
| logtoApp.extraCorsOrigins | list | `[]` | CORS origin exceptions (scheme + host + optional non-default port only). |
| logtoApp.extraPostLogoutRedirectUris | list | `[]` | Post-logout exceptions, same rule. |
| logtoApp.extraRedirectUris | list | `[]` | Non-HTTPS / local / vendor redirect exceptions. The ONLY escape from the derived set. |
| logtoApp.paths | object | `{"postLogoutPath":"","redirectPath":""}` | DECLARED PATHS ONLY. Each must be an absolute path beginning with one `/`, with no authority, query, fragment, dot segment, or percent-encoded `/`. Empty means the app has no browser flow of that kind. |
| logtoApp.paths.postLogoutPath | string | `""` | Post-logout path. Empty for a machine-to-machine app. |
| logtoApp.paths.redirectPath | string | `""` | Login callback path. Empty for a machine-to-machine app. |
| logtoApp.resourceRefs | list | `[]` | Explicit `LogtoResource` CR names this app takes tokens for. A missing ref is a hard `ResourceRefMissing` error, never inferred, so this stays empty until the resource rows for this landscape exist. |
| logtoApp.type | string | `"MachineToMachine"` | Logto application type. |
| logtoApp.vlandscape | string | `"mew"` | Virtual landscape this app resolves its Logto endpoint from (`mew` for production rows, `celebi` for staging). The endpoint itself is DERIVED from `identityRef` plus the platform — never configured per CR. |
| observability | object | `{"alertInterval":"1m","apiVersion":"grafana.integreatly.org/v1beta1","datasourceUids":{"logs":"loki","metrics":"mimir"},"enabled":true,"genericDashboardUid":"atomi-generic-lpsm","instanceSelector":{"matchLabels":{"dashboards":"grafana"}},"path":"files/observability","relativeTimeRangeFrom":600,"repositoryUrl":"https://github.com/AtomiCloud/diene.dotnet-api/blob/main","resyncPeriod":"10m"}` | Grafana Operator rendering of the repository's `observability/` source (docs/standards/observability/primordial-chart.md). The root directory is authoritative; the chart build copies it into the gitignored `files/observability/` before lint/template/package/publish.  The six-gate method legitimately yields ZERO dashboards and ZERO alerts, so every template renders cleanly with none present. No placeholder is ever added just to populate a directory. |
| observability.alertInterval | string | `"1m"` | Alert-group evaluation interval. |
| observability.apiVersion | string | `"grafana.integreatly.org/v1beta1"` | API group/version of the Grafana Operator CRDs. |
| observability.datasourceUids | object | `{"logs":"loki","metrics":"mimir"}` | Platform-pinned datasource UIDs. An alert file's `datasource:` selects one by name; an unknown name is a render-time failure. |
| observability.datasourceUids.logs | string | `"loki"` | LogQL datasource. |
| observability.datasourceUids.metrics | string | `"mimir"` | PromQL datasource. |
| observability.enabled | bool | `true` | Render the GrafanaFolder and any dashboards/alerts found. |
| observability.genericDashboardUid | string | `"atomi-generic-lpsm"` | Generic LPSM dashboard an alert links when it declares no `panel`. |
| observability.instanceSelector | object | `{"matchLabels":{"dashboards":"grafana"}}` | Which Grafana instances on Primordial pick these resources up. |
| observability.path | string | `"files/observability"` | Glob root, relative to the chart directory, for the copied `observability/`. |
| observability.relativeTimeRangeFrom | int | `600` | Lookback window, in seconds, for each rule's instant query. |
| observability.repositoryUrl | string | `"https://github.com/AtomiCloud/diene.dotnet-api/blob/main"` | Repository base URL that every `runbook_url` annotation is built from. |
| observability.resyncPeriod | string | `"10m"` | Dashboard resync cadence. |
| platformDependencies | list | `[{"cache":{"main":{"cpu":1,"credentialMode":"standard","delivery":"local","engine":{"dragonfly":{"snapshot":false}},"ram":"256Mi","rotation":"off","type":"dragonfly"}},"database":{"main":{"cpu":1,"credentialMode":"standard","delivery":"local","engine":{"cnpg":{}},"ram":"512Mi","rotation":"off","storage":"1Gi","type":"cnpg","version":"16"}},"deletionPolicy":{"retainSecret":"1h"},"kv":{"main":{"cpu":1,"credentialMode":"standard","delivery":"local","engine":{"dragonfly":{"snapshot":true}},"ram":"256Mi","rotation":"off","type":"dragonfly"}},"landscape":"lapras","placement":{"preferredHost":"lapras"},"store":{"main":{"credentialMode":"standard","delivery":"local","engine":{"minio":{}},"rotation":"off","storage":"1Gi","type":"minio"}}}]` | Dependency declarations. ONE union-set `PlatformDependency` CR per landscape spanning the `database` / `kv` / `cache` / `store` modules this service needs — it REPLACES the old per-kind postgres/redis/S3 CRs. Every module block is a MAP of named connections, matching `App/Config/settings.yaml`, where `MAIN` is the connection the app resolves.  Dependencies are requested through CRs in EVERY landscape, lapras included: the operator realizes CNPG/Dragonfly/MinIO in-cluster locally and the managed classes from Primordial. There is no local-subchart-vs-cloud-CR toggle and app charts never bundle dependency subcharts. A duplicate landscape is a loud render-time Conflict, never last-write-wins. |
| platformDependencies[0].cache | object | `{"main":{"cpu":1,"credentialMode":"standard","delivery":"local","engine":{"dragonfly":{"snapshot":false}},"ram":"256Mi","rotation":"off","type":"dragonfly"}}` | Cache. EPHEMERAL by contract — no snapshot, safe to lose. Same protocol as kv, opposite durability contract; never point one at the other's instance. |
| platformDependencies[0].database | object | `{"main":{"cpu":1,"credentialMode":"standard","delivery":"local","engine":{"cnpg":{}},"ram":"512Mi","rotation":"off","storage":"1Gi","type":"cnpg","version":"16"}}` | Postgres. The system of record for long-lived truth; `cnpg` is the in-cluster class and its delivery is `local` (the CRD rejects any other pairing). |
| platformDependencies[0].deletionPolicy.retainSecret | string | `"1h"` | How long a materialized secret is retained after the CR is deleted. |
| platformDependencies[0].kv | object | `{"main":{"cpu":1,"credentialMode":"standard","delivery":"local","engine":{"dragonfly":{"snapshot":true}},"ram":"256Mi","rotation":"off","type":"dragonfly"}}` | KV. PERSISTENT — snapshot durability is on, because losing this is losing data, not losing a cache. |
| platformDependencies[0].landscape | string | `"lapras"` | Target landscape. One CR per landscape, single writer. |
| platformDependencies[0].placement.preferredHost | string | `"lapras"` | Required host preference. |
| platformDependencies[0].store | object | `{"main":{"credentialMode":"standard","delivery":"local","engine":{"minio":{}},"rotation":"off","storage":"1Gi","type":"minio"}}` | S3-compatible object storage. db-init creates the bucket MinIO will not. |
| problems | object | `{"apiVersion":"atomi.cloud/v1alpha1","enabled":true,"path":"problems/catalog-v1.json","version":"v1"}` | The Problem catalog row, rendered from the committed `pls problems:export` output. |
| problems.apiVersion | string | `"atomi.cloud/v1alpha1"` | API group/version of the Problem CRD (owned by T3). |
| problems.enabled | bool | `true` | Render the Problem CR. |
| problems.path | string | `"problems/catalog-v1.json"` | Exporter output, relative to the chart directory. COMMITTED, not vendored: it is a real generated artifact and `problems:verify` gates its freshness. Rendering tolerates the file being absent so a fresh checkout stays green before the first export. |
| problems.version | string | `"v1"` | Catalog version. One CR = one version snapshot; a bump is a NEW CR, never an in-place mutation (D8). Must agree with the version segment of the exported file's own `spec`. |
| serviceTree | object | `{"landscape":"lapras","layer":"2","module":"api","platform":"sulfoxide","service":"dotnet-api"}` | Stable service-tree projection (LPSM). Must match the app chart's, and must match `App/Config/settings.yaml`: the exported Problem catalog mints its type URIs from those same four values. |
| serviceTree.landscape | string | `"lapras"` | Landscape. The ONLY overlay axis (R16). |
| serviceTree.layer | string | `"2"` | Architecture layer (application tier). |
| serviceTree.module | string | `"api"` | Module name for the workload these dependencies serve. |
| serviceTree.platform | string | `"sulfoxide"` | Platform name. Also the Primordial namespace and the parent Grafana folder uid. |
| serviceTree.service | string | `"dotnet-api"` | Service name — the REAL identity (R4). |
| virtualLandscapeService | object | `{"apiVersion":"fleet.atomi.cloud/v1alpha1","enabled":false,"serve":false,"vlandscape":"mew"}` | Virtual-landscape serve-set membership. Only a row that SERVES a v-landscape declares one, which is rare; this service is reached through its own landscape's gateway, so the surface exists but is gated OFF. |
| virtualLandscapeService.apiVersion | string | `"fleet.atomi.cloud/v1alpha1"` | API group/version of the VirtualLandscapeService CRD. |
| virtualLandscapeService.enabled | bool | `false` | Render the VirtualLandscapeService CR. OFF: this row does not serve a v-landscape. |
| virtualLandscapeService.serve | bool | `false` | Whether this row serves traffic for the v-landscape. |
| virtualLandscapeService.vlandscape | string | `"mew"` | Virtual landscape this row would join. |
