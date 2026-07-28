# flutter-base-primordial

![Version: 0.1.0](https://img.shields.io/badge/Version-0.1.0-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square) ![AppVersion: 0.1.0](https://img.shields.io/badge/AppVersion-0.1.0-informational?style=flat-square)

Primordial chart for the diene flutter-base mobile client — the LogtoApp identity
CR plus its Grafana Operator folder, dashboards, and alerts.

## What this chart owns (and does not)

This is the **primordial chart** half of the R20 two-chart model. It deploys to
the **Primordial** central cluster, where the logto operator and the Grafana
Operator run.

There is **no app chart half**. This node's deliverable is a signed binary
distributed through the App Store and Play Store; there is no image, no
Deployment, no Service, and no ingress. That is not a gap in this chart — it is
what a mobile row is.

| Rendered                                    | Source                                        |
| ------------------------------------------- | --------------------------------------------- |
| `LogtoApp` (one per app × vlandscape)       | `logtoApp` values                             |
| `GrafanaFolder`                             | service identity                              |
| `GrafanaDashboard` (one per JSON)           | `observability/dashboards/{purpose}.json`     |
| `GrafanaAlertRuleGroup` (one per tier file) | `observability/alerts/{slug}/{severity}.yaml` |

### Deliberately not shipped

Each row below is a mechanism this node **does not have**, not one it has and
disables. Where a surface is absent, there is no values key for it at all — a
chart that renders a resource the app does not use lints green and means nothing.

| Kind                                   | Why                                                                                                                                                                    |
| -------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `PlatformDependency`                   | a mobile client owns **no** database, kv, cache, or object store. It talks to `api.baseUrl` over HTTPS; the backend row owns the dependencies                          |
| `Problem`                              | this app **consumes** backend problem types (`lib/core/problem_catalog.dart` maps endpoint + status → `Problem`). It publishes no catalog and has no `problems:export` |
| `ExternalSecret`                       | nothing here mounts a cluster secret. A public native client holds no confidential credential — that is why `logtoApp.type` is `Native`                                |
| Deployment / Service / Ingress / image | ships to app stores, serves no HTTP                                                                                                                                    |
| `CloudflareDeploy`                     | no edge assets                                                                                                                                                         |
| `VirtualLandscapeService`              | serves no v-landscape                                                                                                                                                  |
| Kargo config                           | centralized on Primordial per R20 — never per service chart                                                                                                            |

## LogtoApp: a native client is not an HTTP sibling

Exactly **one** `LogtoApp` CR per (app × vlandscape) — the single home of all
app-level truth (S6/Q-I36). The mobile client owns its own app identity, so it
**is** the placement owner and `logtoApp.enabled` defaults to `true`.

`type` is pinned to **`Native`** by `values.schema.json` as a `const`, not merely
defaulted. A store-distributed binary is a **public** client: it runs
authorization-code + PKCE and cannot hold a confidential secret, so a
`Traditional` or `MachineToMachine` value here would describe an app that cannot
exist. Making it unrepresentable is cheaper than documenting it.

**Where the derived-URI rule does not reach.** For an HTTP sibling the operator
builds `origin(L) + declaredPath` from the live serve-set. That presupposes an
HTTP origin. This app serves none: it is installed from a store and redeems a
**custom-scheme** callback —
`cloud.atomi.<landscape>.platform.service.app://callback` — which has no origin
to append a path to. So:

- `paths.redirectPath` and `paths.postLogoutPath` are **empty**;
- the four real per-flavor callbacks travel through **`extraRedirectUris`**, the
  standard's declared escape for non-HTTPS/vendor redirects. Here it is
  **load-bearing rather than exceptional**, because a native client has no other
  shape.

Two render-time guards stop that from becoming a silent hole:

1. a client with **neither** a declared path **nor** an explicit callback refuses
   to render — otherwise it would register an app nothing can redirect into, and
   login would fail in the installed binary long after the chart went green;
2. every explicit callback must carry a **URI scheme** — Logto accepts a bare
   path and it fails only at redirect.

The callback list mirrors `auth.redirectUri` in `config/<landscape>.yaml` and the
flavor application ids in `pubspec.yaml`. A divergence means the shipped binary's
callback is not registered.

The path slots stay declarable so a later universal-link path is validated the
same way an HTTP sibling's is.

## Observability rendering

The repository root `observability/` is authoritative. Helm cannot read outside
the chart directory, so the chart **build** copies it into the gitignored
`files/observability/` before lint, template, package, or publish:

```sh
mkdir -p infra/primordial_chart/files && cp -r observability infra/primordial_chart/files/
```

The copy is never hand-edited and never committed. Mechanical mappings:

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

`observability.datasourceUids` carries a **`frontend`** entry (`faro`) that the
backend siblings do not need. This node ships a live client RUM rail
(`lib/observability/faro.dart`, `lib/integration/observability_wiring.dart`
projecting the LPSM label set), so a mobile signal has a datasource to be
alerted on.

`helm template` **refuses to render** when a severity filename is not
`critical|warning|info.yaml`, an alert is missing
`title`/`datasource`/`expr`/`summary`/`description`, a title exceeds 48
characters, an alert set has no `runbook.md`, a dashboard is not valid JSON or
its uid drifts from the deterministic value, a `datasource:` names an unpinned
UID, or required `serviceTree` values are absent. Each of those was verified to
turn `helm template` rc=1, not read off the sibling.

### Dashboards and alerts are OWED, and this chart says so rather than faking it

`helm template` today renders **two** resources — `GrafanaFolder` and
`LogtoApp` — and **zero** `GrafanaDashboard` / `GrafanaAlertRuleGroup`.

This is **not** a values guard: `observability.enabled` already defaults `true`.
The dashboard and alert templates ship and work; there is simply no content for
them to iterate over. This repository has **no root `observability/` directory
at all** — unlike the backend siblings, which ship the directory containing only
a `README.md`.

The mechanism is proven, not assumed. With a throwaway
`files/observability/dashboards/overview.json` plus
`alerts/faro-init-failure/{critical.yaml,runbook.md}` in place, `helm template`
rendered **four** kinds including `GrafanaDashboard` and
`GrafanaAlertRuleGroup`, with LPSM labels injected, the 🚨 prefix derived from
the filename, and the `faro` datasource resolved. The fixture was then removed:
authoring real dashboard and alert content is a different skill and a different
review.

**So the goal's `helm template` smoke row — "renders dashboards and alerts" — is
NOT fully satisfied by this chart, and is reported as owed.** What is owed is
the **content** under a root `observability/` directory (a curated dashboard
whose uid is `platform-service-overview`, and at least one alert set with its
`runbook.md`), not any change to this chart. Asserting those kinds in the gate
today would make it red for a deliberate, documented absence; shipping a green
`helm template` as if the row were met would be a vacuous smoke.

## Local install

A bare k3d cluster has none of these CRDs. Apply the test-only fixtures in
[`crds-local/`](./crds-local/README.md) first — they are excluded from the
packaged chart and are not named `crds/`, so Helm never auto-installs them.

`scripts/validate/chart-install.sh` does this end to end. **It creates and
destroys its own k3d cluster and refuses to install into a context it did not
create.** That guard is not ceremonial: there is no local verification cluster
on a developer box here, and `kubectl` answers anyway — the ambient context
during development was a remote **DigitalOcean** managed cluster, and it
_changed_ mid-task. An unguarded `helm install` would not fail and would print no
warning; it would simply succeed against production-adjacent infrastructure.

## Gates

| Gate                 | Runs                                   | Bound to                                                               |
| -------------------- | -------------------------------------- | ---------------------------------------------------------------------- |
| `a-chart-primordial` | `scripts/validate/chart-primordial.sh` | `^(infra/primordial_chart/.*\|scripts/validate/chart-primordial\.sh)$` |

`helm lint` reads `values.schema.json` itself, so that one hook covers both the
lint and the schema row. The validator asserts on the **rendered kinds**, never
on `helm template`'s exit code — a successful render of nothing would otherwise
pass.

The install smoke is **not** a pre-commit hook: it needs Docker and takes
minutes. It is a hand-run and CI-run script.

## Requirements

Kubernetes: `>=1.27.0-0`

## Values

| Key                                   | Type   | Default                                                        | Description                                                                                                       |
| ------------------------------------- | ------ | -------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------- |
| labelPrefix                           | string | `"atomi.cloud"`                                                | Prefix for every service-tree label and annotation helper. Single configurable key (R16/B26).                     |
| serviceTree.platform                  | string | `"platform"`                                                   | Platform name. Also the Primordial namespace and the parent Grafana folder uid.                                   |
| serviceTree.service                   | string | `"service"`                                                    | Service name. Dash-less: every resource name is `<service>-<token>`.                                              |
| serviceTree.module                    | string | `"app"`                                                        | Module name for the workload these resources serve.                                                               |
| serviceTree.layer                     | string | `"2"`                                                          | Architecture layer (application tier).                                                                            |
| logtoApp.enabled                      | bool   | `true`                                                         | Render the LogtoApp CR. On: the mobile client owns its own app identity.                                          |
| logtoApp.apiVersion                   | string | `"fleet.atomi.cloud/v1alpha1"`                                 | API group/version of the LogtoApp CRD.                                                                            |
| logtoApp.identityRef                  | string | `"mew"`                                                        | Virtual landscape this app resolves its Logto endpoint from. The endpoint is derived, never configured.           |
| logtoApp.type                         | string | `"Native"`                                                     | Pinned by schema `const`. A store-distributed public client cannot hold a confidential secret.                    |
| logtoApp.paths.redirectPath           | string | `""`                                                           | Empty: no HTTP origin exists to derive `origin(L) + declaredPath` from.                                           |
| logtoApp.paths.postLogoutPath         | string | `""`                                                           | Empty, for the same reason.                                                                                       |
| logtoApp.resourceRefs                 | list   | `[]`                                                           | Explicit `LogtoResource` CR names. A missing ref is a hard error, never inferred.                                 |
| logtoApp.extraRedirectUris            | list   | four `cloud.atomi.<landscape>.platform.service.app://callback` | The custom-scheme callbacks this native client actually redeems, one per store track. Load-bearing, not optional. |
| logtoApp.extraPostLogoutRedirectUris  | list   | same four                                                      | `logto_dart_sdk` signs out against the same callback it signed in with.                                           |
| logtoApp.extraCorsOrigins             | list   | `[]`                                                           | None: a native client issues no browser cross-origin request.                                                     |
| observability.enabled                 | bool   | `true`                                                         | Render the GrafanaFolder and any dashboards/alerts found.                                                         |
| observability.apiVersion              | string | `"grafana.integreatly.org/v1beta1"`                            | API group/version of the Grafana Operator CRDs.                                                                   |
| observability.path                    | string | `"files/observability"`                                        | Glob root, relative to the chart directory, for the copied `observability/`.                                      |
| observability.instanceSelector        | object | `{"matchLabels":{"dashboards":"grafana"}}`                     | Which Grafana instances on Primordial pick these resources up.                                                    |
| observability.resyncPeriod            | string | `"10m"`                                                        | Dashboard resync cadence.                                                                                         |
| observability.alertInterval           | string | `"1m"`                                                         | Alert-group evaluation interval.                                                                                  |
| observability.relativeTimeRangeFrom   | int    | `600`                                                          | Lookback window, in seconds, for each rule's instant query.                                                       |
| observability.datasourceUids.metrics  | string | `"mimir"`                                                      | PromQL datasource.                                                                                                |
| observability.datasourceUids.logs     | string | `"loki"`                                                       | LogQL datasource.                                                                                                 |
| observability.datasourceUids.frontend | string | `"faro"`                                                       | Client RUM datasource. Present because this node ships a live Faro rail.                                          |
| observability.repositoryUrl           | string | `"https://github.com/AtomiCloud/diene.flutter-base/blob/main"` | Repository base URL every `runbook_url` annotation is built from.                                                 |
| observability.genericDashboardUid     | string | `"atomi-generic-lpsm"`                                         | Generic LPSM dashboard an alert links when it declares no `panel`.                                                |
