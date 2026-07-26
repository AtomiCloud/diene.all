# go-consumer-primordial

![Version: 0.1.0](https://img.shields.io/badge/Version-0.1.0-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square) ![AppVersion: 0.1.0](https://img.shields.io/badge/AppVersion-0.1.0-informational?style=flat-square)

Primordial chart for the diene go-consumer service — the T3 CR set (PlatformDependency, Problem catalog, optional LogtoApp) plus its Grafana Operator dashboards and alerts

## What this chart owns (and does not)

This is the **primordial chart** half of the R20 two-chart model. It deploys to
the **Primordial** central cluster, where ArgoCD, Kargo, the dependency operator,
and the Grafana Operator run. Locally (k3d/lapras) it installs into the same
cluster as the app chart.

| Rendered                                                | Source                                        |
| ------------------------------------------------------- | --------------------------------------------- |
| `PlatformDependency` (one per landscape)                | `platformDependencies` values                 |
| `Problem` (one per landscape × version)                 | `files/problems.json`                         |
| `LogtoApp` (one per app × vlandscape, values-gated)     | `logtoApp` values                             |
| `GrafanaFolder`                                         | service identity                              |
| `GrafanaDashboard` (one per JSON)                       | `observability/dashboards/{purpose}.json`     |
| `GrafanaAlertRuleGroup` (one per tier file)             | `observability/alerts/{slug}/{severity}.yaml` |

Adding a dependency or a dashboard means editing **this** chart, never
hand-provisioning.

### Deliberately not shipped

| Kind                      | Why                                                                                                                 |
| ------------------------- | ------------------------------------------------------------------------------------------------------------------- |
| `CloudflareDeploy`        | this template ships **no edge assets** — there is nothing to deploy to the edge, so the surface would be dead weight |
| `VirtualLandscapeService` | this row **serves no v-landscape** (the consumer has no HTTP surface); the CR is rare and belongs to rows that do    |
| Kargo config              | centralized on Primordial per R20 — never per service chart                                                         |

## PlatformDependency: one union CR, every landscape

Dependencies are **always** requested through CRs, in **every** landscape (B30).
lapras runs the dependency operator too and realizes the in-cluster classes
(CNPG, Dragonfly, MinIO); cloud landscapes get the managed classes (Neon,
Upstash, Tigris). There is no local-subchart-vs-cloud-CR toggle, and app charts
never bundle dependency sub-charts.

One **union-set** CRD spans the `database` / `kv` / `cache` / `store` modules —
per-kind postgres/redis/S3 CRs are replaced. The **redis-streams transport rides
the kv/cache module**: there is no transport CR. Each entry is one CR for one
landscape with a single writer; a duplicate landscape is a loud render-time
`Conflict`, and a row declaring zero modules is rejected.

The `store` module serves **both** keyed storage adapters the service config
declares (`storage.MAIN` and `storage.ARCHIVE`) — two logical buckets on one
object-storage dependency, not two CRs. db-init creates the buckets MinIO will
not.

## Problem catalog

`files/problems.json` is the committed output of the service's `problems:export`,
which serializes the catalog through the **published**
`diene.go-errors-problems` builder (`Catalog.ToCRDContent`). Each entry's `type`
is the fully-minted RFC 9457 URI produced at export time by the single-source
builder `problem.TypeURI` (C0 §2) — this chart never reconstructs one from
segments.

One CR per `(platform, service, landscape, version)` row. A release
re-materializes the entire row in one write; a version bump is a **new** CR,
never an in-place `spec.version` mutation (D8). Rendering tolerates the file
being absent so a fresh checkout stays green before the first export.

> `goals/error-portal.md` §"Generation pipeline" describes the exporter writing
> plain manifests into `templates/problems/*.yaml`. This chart instead consumes
> the exporter's JSON through `.Files.Get` and wraps it here, so the CR's identity
> and LPSM projection come from the same chart values as every other resource.

## LogtoApp: shipped, gated off

Exactly **one** `LogtoApp` CR per (app × vlandscape) — the single home of all
app-level truth (S6/Q-I36); the old per-row fragment CRs are abolished.

**Placement-owner condition:** render this only when this chart is the selected
placement owner for the app — the chart that declares the app's serve-set. A
worker with no HTTP surface is normally **not** that chart, so `logtoApp.enabled`
defaults to `false`. The surface still ships so an app-owning consumer built from
this template only has to flip the flag; `values.example.yaml` shows the ON shape.

Redirect, post-logout, and CORS values are **DERIVED**, never declared per row:
the operator resolves the live serve-set and builds `origin(L) + declaredPath`.
This chart declares **paths only**, validated as absolute RFC 3986 paths.
Non-HTTPS/local/vendor exceptions go through the `extra*` lists — the only escape,
with no environment-specific implicit branch. `resourceRefs` names
`LogtoResource` CRs explicitly; a missing ref is a hard error, never inferred.

## Observability rendering

The repository root `observability/` is authoritative. Helm cannot read outside
the chart directory, so the chart **build** copies it into the gitignored
`files/observability/` before lint, template, package, or publish:

```sh
mkdir -p infra/primordial_chart/files && cp -r observability infra/primordial_chart/files/
```

The copy is never hand-edited and never committed. Mechanical mappings
(`docs/standards/observability/primordial-chart.md`):

- service identity → one `GrafanaFolder`, uid `<platform>-<service>-folder`,
  parented to the platform folder `<platform>`;
- `dashboards/{purpose}.json` → one `GrafanaDashboard`, uid
  `<platform>-<service>-<purpose>`;
- `alerts/{slug}/{severity}.yaml` → one `GrafanaAlertRuleGroup` named
  `<platform>-<service>-<slug>-<severity>`, holding exactly **one** inline rule.

Source definitions are pure Grafana-domain objects — no Kubernetes wrapper, no
hand-authored LPSM. The renderer derives severity and the 🚨/⚠️/ℹ️ title prefix
from the **filename** (a mismatch is unrepresentable), merges the service-tree
labels, and builds `runbook_url`, `__dashboardUid__`, and `__panelId__`.

`helm template` **refuses to render** when a severity filename is not
`critical|warning|info.yaml`, an alert is missing `title`/`datasource`/`expr`/
`summary`/`description`, a title exceeds 48 characters, an alert set has no
`runbook.md`, a dashboard is not valid JSON or its uid drifts from the
deterministic value, a `datasource:` names an unpinned UID, or required
`serviceTree` values are absent.

The six-gate method legitimately yields **zero** dashboards and **zero** alerts.
Every template renders cleanly with none present, and no placeholder is ever
added just to populate a directory.

## Local install

A bare k3d cluster has none of these CRDs. Apply the test-only fixtures in
[`crds-local/`](./crds-local/README.md) first — they are excluded from the
packaged chart and are not named `crds/`, so Helm never auto-installs them.

## Values overlays

Two **independent stacked** dimensions (R16/B26), never a cross-product:

```sh
helm upgrade --install goconsumer-primordial infra/primordial_chart --namespace diene \
  -f infra/primordial_chart/values.yaml \
  -f infra/primordial_chart/values.lapras.yaml \
  -f infra/primordial_chart/values.<cluster>.yaml
```

## Version alignment (per-service promotion)

This chart carries the **same** semver as the app chart and the image tag — chart
`version` == image `Tag`, which is what Kargo aligns on. Both charts go through
the identical one-semver CI path (`scripts/ci/helm.sh` sets `appVersion` to the
image version and packages at that version), so a promotion is one number moving
in one service row. No carbon bump, no umbrella/release-train, no downstream
dispatch chain.

## Requirements

Kubernetes: `>=1.27.0-0`

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| dependencyApiVersion | string | `"fleet.atomi.cloud/v1alpha1"` | API group/version of the dependency-operator CRs. |
| labelPrefix | string | `"atomi.cloud"` | Prefix used by every service-tree label and annotation helper. Single configurable key (R16/B26) — never hard-coded inside a helper. |
| logtoApp | object | `{"apiVersion":"fleet.atomi.cloud/v1alpha1","enabled":false,"extraCorsOrigins":[],"extraPostLogoutRedirectUris":[],"extraRedirectUris":[],"identityRef":"mew","paths":{"postLogoutPath":"","redirectPath":""},"resourceRefs":[],"type":"MachineToMachine"}` | One vlandscape-targeted LogtoApp per app, rendered ONLY when this chart is the selected PLACEMENT OWNER for the app (S6/Q-I36).  PLACEMENT-OWNER CONDITION: the owner is the chart that declares the app's serve-set. This template serves no HTTP and a worker is normally NOT the owner, so the default is OFF — but the surface ships so an app-owning consumer built from this template only flips `enabled`. See `values.example.yaml` for the ON shape. |
| logtoApp.apiVersion | string | `"fleet.atomi.cloud/v1alpha1"` | API group/version of the LogtoApp CRD. |
| logtoApp.enabled | bool | `false` | Render the LogtoApp CR. Off unless this chart owns the app's placement. |
| logtoApp.extraCorsOrigins | list | `[]` | CORS origin exceptions (scheme + host + optional non-default port only). |
| logtoApp.extraPostLogoutRedirectUris | list | `[]` | Post-logout exceptions, same rule. |
| logtoApp.extraRedirectUris | list | `[]` | Non-HTTPS / local / vendor redirect exceptions. The ONLY escape from the derived set; no environment-specific implicit branch exists. |
| logtoApp.identityRef | string | `"mew"` | Virtual landscape this app resolves its Logto endpoint from (`mew` for prod rows, `celebi` for staging). The endpoint itself is DERIVED from identityRef plus the namespace — never configured per CR. |
| logtoApp.paths | object | `{"postLogoutPath":"","redirectPath":""}` | DECLARED PATHS ONLY. Redirect, post-logout, and CORS values are DERIVED by the operator from the live serve-set (`origin(L) + declaredPath`); a chart never writes a per-row redirect URI. Each must be an absolute path beginning with one `/`, with no authority, query, fragment, dot segment, or percent-encoded `/`. |
| logtoApp.paths.postLogoutPath | string | `""` | Post-logout path. Empty for a machine-to-machine app. |
| logtoApp.paths.redirectPath | string | `""` | Login callback path. Empty for a machine-to-machine app. |
| logtoApp.resourceRefs | list | `[]` | Explicit LogtoResource CR names this app takes tokens for. A missing ref is a hard `ResourceRefMissing` error, never inferred. |
| logtoApp.type | string | `"MachineToMachine"` | Logto application type. The worker authenticates to published APIs with client credentials, so machine-to-machine is the shape it would take. |
| observability | object | `{"alertInterval":"1m","apiVersion":"grafana.integreatly.org/v1beta1","datasourceUids":{"logs":"loki","metrics":"mimir"},"enabled":true,"genericDashboardUid":"atomi-generic-lpsm","instanceSelector":{"matchLabels":{"dashboards":"grafana"}},"path":"files/observability","relativeTimeRangeFrom":600,"repositoryUrl":"https://github.com/AtomiCloud/diene.go-consumer/blob/main","resyncPeriod":"10m"}` | Grafana Operator rendering of the repository's `observability/` source (docs/standards/observability/primordial-chart.md). The root directory is authoritative; the chart build copies it into the gitignored `files/observability/` before lint/template/package/publish.  The six-gate method legitimately yields ZERO dashboards and ZERO alerts, so every template renders cleanly with none present. No placeholder is ever added just to populate a directory. |
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
| observability.repositoryUrl | string | `"https://github.com/AtomiCloud/diene.go-consumer/blob/main"` | Repository base URL that every `runbook_url` annotation is built from. |
| observability.resyncPeriod | string | `"10m"` | Dashboard resync cadence. |
| platformDependencies | list | `[{"cache":{"cpu":1,"credentialMode":"standard","delivery":"replicated","ram":"512Mi","rotation":"on","type":"dragonfly"},"database":{"cpu":1,"credentialMode":"standard","delivery":"external","engine":{"neon":{"tier":"launch"}},"providerAccountRef":"nonprod-neon","ram":"1Gi","rotation":"on","storage":"10Gi","type":"neon","version":"16"},"deletionPolicy":{"retainSecret":"168h"},"kv":{"credentialMode":"standard","delivery":"external","engine":{"upstash":{"eviction":false}},"providerAccountRef":"nonprod-upstash","rotation":"on","type":"upstash"},"landscape":"mew","placement":{"preferredHost":"raichu"},"store":{"credentialMode":"standard","delivery":"external","providerAccountRef":"nonprod-tigris","rotation":"on","type":"tigris"}}]` | Dependency declarations. ONE union-set `PlatformDependency` CR per landscape spanning the `database` / `kv` / `cache` / `store` modules this service needs. Dependencies are requested through CRs in EVERY landscape (B30) — the operator realizes CNPG/Dragonfly/MinIO in-cluster locally and the managed classes from Primordial. There is no local-subchart vs cloud-CR toggle and no per-kind CR.  The redis-streams transport RIDES the kv/cache module: there is NO transport CR. A duplicate landscape is a loud render-time Conflict. |
| platformDependencies[0].cache | object | `{"cpu":1,"credentialMode":"standard","delivery":"replicated","ram":"512Mi","rotation":"on","type":"dragonfly"}` | Ephemeral cache (dragonfly class, no disk). |
| platformDependencies[0].database | object | `{"cpu":1,"credentialMode":"standard","delivery":"external","engine":{"neon":{"tier":"launch"}},"providerAccountRef":"nonprod-neon","ram":"1Gi","rotation":"on","storage":"10Gi","type":"neon","version":"16"}` | Postgres MAIN: the system of record for long-lived truth. |
| platformDependencies[0].deletionPolicy.retainSecret | string | `"168h"` | How long a materialized secret is retained after the CR is deleted. |
| platformDependencies[0].kv | object | `{"credentialMode":"standard","delivery":"external","engine":{"upstash":{"eviction":false}},"providerAccountRef":"nonprod-upstash","rotation":"on","type":"upstash"}` | KV (Upstash class). Preferred on hot paths per S19/Q-WH2, and the host of the redis-streams consumer-group transport. |
| platformDependencies[0].landscape | string | `"mew"` | Target landscape. May name a vlandscape; one CR per landscape, single writer. |
| platformDependencies[0].placement.preferredHost | string | `"raichu"` | Required host preference for vlandscape externals. |
| platformDependencies[0].store | object | `{"credentialMode":"standard","delivery":"external","providerAccountRef":"nonprod-tigris","rotation":"on","type":"tigris"}` | S3-compatible object storage, serving BOTH the `MAIN` and `ARCHIVE` keyed adapters the config declares: one storage dependency, two logical buckets. db-init creates the buckets MinIO will not. |
| problems | object | `{"apiVersion":"atomi.cloud/v1alpha1","enabled":true,"landscapes":["mew"],"path":"files/problems.json","version":"v1"}` | The Problem catalog row, rendered from the committed `problems:export` output. |
| problems.apiVersion | string | `"atomi.cloud/v1alpha1"` | API group/version of the Problem CRD (owned by T3). |
| problems.enabled | bool | `true` | Render the Problem CR set. |
| problems.landscapes | list | `["mew"]` | Landscapes to materialize the row for. Problem content is landscape-independent; rows for the same (platform, service, version, id) are expected to be byte-identical. |
| problems.path | string | `"files/problems.json"` | Exporter output, relative to the chart directory. Committed, not vendored: it is a real generated artifact of `problems:export`. Rendering tolerates the file being absent so a fresh checkout stays green before the first export. |
| problems.version | string | `"v1"` | Catalog version. One CR = one version snapshot; a bump is a NEW CR, never an in-place mutation (D8). |
| serviceTree | object | `{"layer":"2","module":"worker","platform":"diene","service":"goconsumer"}` | Stable service-tree projection (LPSM). Landscape and cluster slots are added by the two independent overlay dimensions; the base file never carries them. |
| serviceTree.layer | string | `"2"` | Architecture layer (application tier). |
| serviceTree.module | string | `"worker"` | Module name for the workload these dependencies serve. |
| serviceTree.platform | string | `"diene"` | Platform name. Also the Primordial namespace and the parent Grafana folder uid. |
| serviceTree.service | string | `"goconsumer"` | Service name. Dash-less: every resource name is `<service>-<token>`. |
