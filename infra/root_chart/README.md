# dotnet-api

![Version: 0.0.0](https://img.shields.io/badge/Version-0.0.0-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square) ![AppVersion: 0.0.0](https://img.shields.io/badge/AppVersion-0.0.0-informational?style=flat-square)

Runtime app chart for the diene .NET API — Deployment, Service, HTTPRoute, HPA, ExternalSecret, the vendored settings ConfigMap, and the hook-scoped db-init Job

## What this chart owns (and does not)

This is the **app chart** half of the two-chart model (R20). It is PURE RUNTIME and deploys to
application/landscape clusters:

| Resource                               | Why                                                          |
| -------------------------------------- | ------------------------------------------------------------ |
| `Deployment` `dotnet-api-api`          | the ASP.NET Core host                                        |
| `Service` `dotnet-api-api`             | the stable in-cluster address                                |
| `HTTPRoute` `dotnet-api-api`           | attachment to the platform's Gateway                         |
| `HorizontalPodAutoscaler`              | owns the replica count while enabled                         |
| `Job` `dotnet-api-dbinit`              | the one-shot, hook-scoped migration/seed entry point         |
| `ConfigMap` `-config` / `-dbinitconfig`| the build-time vendored application config YAMLs             |
| `ExternalSecret` `dotnet-api-secrets`  | materializes the service secret from the platform SecretStore |

It owns **no Grafana resources** — dashboards and alerts live in the sibling
[primordial chart](../primordial_chart/README.md), which also declares every dependency.
It owns **no dependency sub-charts** and **no cron surface**: postgres, KV, cache, and object
storage are requested through the primordial chart's `PlatformDependency` CR in **every**
landscape, lapras included.

## Dependency-blind probes (R20)

Liveness **and** readiness both `GET /` — the info endpoint. That endpoint reports the
process, never postgres/kv/cache/store reachability, and it stays that way deliberately: if
the probes consulted dependencies, a database blip would fail every probe at once and the
kubelet would roll the whole serving Deployment, turning a degraded dependency into a total
outage. Dependency reachability belongs to `db-init` and to alerting.

A startup probe covers a slow first boot so that slowness never reaches the liveness probe.

## Graceful shutdown is one number, not two

`shutdown.timeoutSeconds` is projected into the container as
`ASPNETCORE_SHUTDOWNTIMEOUTSECONDS`, and `shutdown.terminationGracePeriodSeconds` becomes the
pod's grace period. `_helpers.tpl` **fails the render** when the grace period does not exceed
the drain budget — otherwise the kubelet would SIGKILL a host that is still finishing
in-flight requests, and nothing would report it.

`app.port` is stated once and becomes the container port, the Service `targetPort` (by NAME),
and the address Kestrel binds via `ASPNETCORE_URLS`. A changed port cannot leave a probe
pointing at a closed socket.

## db-init is hook-scoped, and the rollout stays a rolling update

`dotnet-api-dbinit` runs the SAME image with the `db-init` argument
(`App/StartUp/RunMode.cs`) and carries **both** hook systems — helm
`pre-install,pre-upgrade` and ArgoCD `PreSync` — plus
`hook-delete-policy: before-hook-creation` so a re-run is not an immutable-field conflict.
Sync waves order it after the secret/config and ahead of the Deployment's implicit wave 0.

Because it is a **hook**, helm keeps it out of the release's ordinary resource set entirely:
`helm template --no-hooks` renders zero Jobs. Nothing about the Job is checksummed into the
Deployment's pod template either. The Deployment therefore always performs an ordinary
`RollingUpdate`, with the migration having already run as a separate hook-scoped Job.

Helm hooks and ArgoCD PreSync both run before the release's ordinary resources, so the Job
mounts its **own** hook-scoped copy of the config ConfigMap — the Deployment's copy does not
exist yet on a first install. For the same reason the secret `envFrom` is `optional` and
db-init must be re-runnable: the migration is idempotent and the seed is seed-if-not-exists.

## Build-phase config vendoring

The application config YAMLs live **outside** the chart in `App/Config/` — the app reads them
directly in local dev. Helm cannot reference files outside the chart directory, so the helm
**build** step copies them in:

```sh
pls helm:vendor    # -> infra/root_chart/files/config/
```

That directory is **gitignored and never committed**; it is regenerated on every lint,
render, package, and publish. Every template guards it with `.Files.Glob`, so `helm lint`,
`helm template`, and `helm install` all stay green with zero files present.

When the copy has **not** run the chart renders **no ConfigMap and no mount at all** —
deliberately, not as a degraded fallback. The image bakes `Config/` in at this same mount
path, so an empty ConfigMap would shadow those defaults with an empty directory and the host
would find no `settings.yaml` at all.

## Values overlays

Landscape is the ONLY axis (R16) — a service repository has no cluster dimension:

```sh
helm upgrade --install dotnet-api infra/root_chart -f infra/root_chart/values.raichu.yaml
```

Landscapes are `lapras` (local), `castform` (preview), `pichu` (dev), `pikachu` (staging),
`raichu` (production). The base `values.yaml` is a complete, installable **local** release, so
a forgotten overlay degrades to the local shape rather than to production.

`values.schema.json` (R17) validates the base values and every overlay; `pls helm:lint:all`
lints each overlay explicitly with `-f`, because linting the chart alone would only ever prove
the base layer.

## Secrets

One `ExternalSecret` reads the platform SecretStore that carbon creates through the SoS chain
— 1 platform = 1 SecretStore. The service **assumes** the store exists; it never provisions
one, there is no `sulfoxide-bromine:` values key, and there is no PushSecret. Shared and
service folders are fanned in with disjoint key prefixes (`SHARED_` and `DOTNET_API_`) so a
platform-wide key cannot silently shadow a service key of the same name.

## Version alignment

ONE semver spans the image tag and **both** charts' `version` and `appVersion` fields — chart
`version` == image `Tag` is what Kargo aligns on. `scripts/validate/chart-versions.sh` is the
gate; run it with `pls helm:versions`.

## Requirements

Kubernetes: `>=1.27.0-0`

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| app | object | `{"args":["server"],"env":[],"port":8080,"replicas":1,"resources":{"limits":{"memory":"512Mi"},"requests":{"cpu":"100m","memory":"192Mi"}},"rollingUpdate":{"maxSurge":1,"maxUnavailable":0}}` | The long-running ASP.NET Core host. |
| app.args | list | `["server"]` | Arguments appended to the image ENTRYPOINT. `server` is also the no-argument default; naming it makes the workload's mode explicit next to the db-init Job's. |
| app.env | list | `[]` | Extra environment variables (`ATOMI_X__Y` overrides, R14/R21). |
| app.port | int | `8080` | Container port. Projected as `ASPNETCORE_URLS` so the declared port and the port Kestrel actually binds cannot drift apart. |
| app.replicas | int | `1` | Replica count. Ignored once `autoscaling.enabled` is on and the HPA owns the field. |
| app.resources | object | `{"limits":{"memory":"512Mi"},"requests":{"cpu":"100m","memory":"192Mi"}}` | Resource requests and limits. |
| app.rollingUpdate | object | `{"maxSurge":1,"maxUnavailable":0}` | Rolling-update knobs. The db-init hook Job must never force a recreation, so `RollingUpdate` is the only strategy this chart renders (R20). |
| app.rollingUpdate.maxSurge | int | `1` | Maximum surge pods during a rollout. |
| app.rollingUpdate.maxUnavailable | int | `0` | Maximum unavailable pods during a rollout. |
| autoscaling | object | `{"apiVersion":"autoscaling/v2","behavior":{},"enabled":true,"maxReplicas":3,"minReplicas":1,"targetCPUUtilizationPercentage":80,"targetMemoryUtilizationPercentage":null}` | Horizontal Pod Autoscaler. When enabled the Deployment's `replicas` field is omitted so the HPA owns the scale and a helm upgrade cannot reset it. |
| autoscaling.apiVersion | string | `"autoscaling/v2"` | API group/version of the HPA. |
| autoscaling.behavior | object | `{}` | Scaling behavior, passed through verbatim. Empty renders no `behavior` block. |
| autoscaling.enabled | bool | `true` | Render the HPA. |
| autoscaling.maxReplicas | int | `3` | Upper bound. |
| autoscaling.minReplicas | int | `1` | Lower bound. |
| autoscaling.targetCPUUtilizationPercentage | int | `80` | Target average CPU utilization, in percent. Null removes the CPU metric. |
| autoscaling.targetMemoryUtilizationPercentage | string | `nil` | Target average memory utilization, in percent. Null removes the memory metric. |
| config | object | `{"enabled":true,"mountPath":"/app/Config","path":"files/config","syncWave":"-2"}` | Application config YAMLs bundled as a ConfigMap. In local dev they live OUTSIDE the chart (`App/Config/`) and the app reads them directly; helm cannot reference files outside the chart directory, so the helm BUILD step (`pls helm:vendor`) copies them into `infra/root_chart/files/config/`. That directory is GITIGNORED and never committed — regenerated per build. Rendering tolerates it being absent so lint and template stay green before the copy runs. |
| config.enabled | bool | `true` | Render the config ConfigMap and mount it into both workloads. |
| config.mountPath | string | `"/app/Config"` | Mount path inside the container. The layered YAML is read relative to the content root, which the Dockerfile sets to `/app`, and the loader looks for `Config/settings.yaml`. |
| config.path | string | `"files/config"` | Glob root, relative to the chart directory, for the vendored YAMLs. |
| config.syncWave | string | `"-2"` | Sync wave. Config lands with the secret, before db-init. |
| containerSecurityContext | object | `{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]},"readOnlyRootFilesystem":true}` | Container-level security context shared by the app and db-init containers (M26). |
| dbInit | object | `{"activeDeadlineSeconds":600,"args":["db-init"],"backoffLimit":3,"enabled":true,"env":[],"resources":{"limits":{"memory":"512Mi"},"requests":{"cpu":"100m","memory":"192Mi"}},"syncWave":"-1","ttlSecondsAfterFinished":300}` | One-shot db-init entry point. Runs as a helm `pre-install,pre-upgrade` hook AND an ArgoCD `PreSync` hook, ordered ahead of the Deployment. Its checksum is deliberately NOT coupled into the Deployment's pod template: a migration must never trigger app recreation. |
| dbInit.activeDeadlineSeconds | int | `600` | Hard wall-clock ceiling for one db-init run. |
| dbInit.args | list | `["db-init"]` | Arguments appended to the image ENTRYPOINT. `db-init` is the mode `App/StartUp/RunMode.cs` accepts. |
| dbInit.backoffLimit | int | `3` | Job retry budget before the pre-sync hook is declared failed. |
| dbInit.enabled | bool | `true` | Render the db-init hook Job. |
| dbInit.env | list | `[]` | Extra environment variables for the db-init pod only. |
| dbInit.resources | object | `{"limits":{"memory":"512Mi"},"requests":{"cpu":"100m","memory":"192Mi"}}` | db-init resource requests and limits. |
| dbInit.syncWave | string | `"-1"` | Sync wave. Greater than `secret.syncWave` and less than the Deployment's implicit 0. |
| dbInit.ttlSecondsAfterFinished | int | `300` | Seconds the completed Job is retained for inspection. |
| health | object | `{"liveness":{"failureThreshold":3,"initialDelaySeconds":15,"periodSeconds":30,"timeoutSeconds":5},"path":"/","readiness":{"failureThreshold":3,"initialDelaySeconds":5,"periodSeconds":10,"timeoutSeconds":3},"startup":{"enabled":true,"failureThreshold":30,"periodSeconds":5,"timeoutSeconds":3}}` | Liveness AND readiness both target the `GET /` info endpoint and are deliberately DEPENDENCY-BLIND (R20): the endpoint reports the process, never postgres/kv/cache/storage reachability. A database blip must degrade the service, never roll every serving pod. Dependency reachability belongs to db-init and to alerting. |
| health.liveness.failureThreshold | int | `3` | Consecutive failures before the kubelet restarts the container. |
| health.liveness.initialDelaySeconds | int | `15` | Seconds before the first liveness probe. |
| health.liveness.periodSeconds | int | `30` | Liveness probe interval. |
| health.liveness.timeoutSeconds | int | `5` | Liveness probe timeout. |
| health.path | string | `"/"` | HTTP path both probes call. `GET /` is the info endpoint (App/Modules/Info). |
| health.readiness.failureThreshold | int | `3` | Consecutive failures before the pod is taken out of the Service. |
| health.readiness.initialDelaySeconds | int | `5` | Seconds before the first readiness probe. |
| health.readiness.periodSeconds | int | `10` | Readiness probe interval. |
| health.readiness.timeoutSeconds | int | `3` | Readiness probe timeout. |
| health.startup.enabled | bool | `true` | Render a startup probe so a slow first boot does not trip liveness. |
| health.startup.failureThreshold | int | `30` | Attempts before the container is declared failed to start. |
| health.startup.periodSeconds | int | `5` | Startup probe interval. |
| health.startup.timeoutSeconds | int | `3` | Startup probe timeout. |
| httpRoute | object | `{"annotations":{},"apiVersion":"gateway.networking.k8s.io/v1","enabled":true,"hostnames":[],"parentRefs":[{"name":"kgateway","namespace":"kgateway-system"}],"pathPrefix":"/"}` | Gateway API HTTPRoute. Ingress is a gateway concern; this chart only attaches to a Gateway the platform already runs, and never creates one. |
| httpRoute.annotations | object | `{}` | Extra annotations for the HTTPRoute. |
| httpRoute.apiVersion | string | `"gateway.networking.k8s.io/v1"` | API group/version of the Gateway API HTTPRoute. |
| httpRoute.enabled | bool | `true` | Render the HTTPRoute. |
| httpRoute.hostnames | list | `[]` | Hostnames. EMPTY means "every hostname the parent listener accepts", which is the correct local shape; landscape overlays name the real host. |
| httpRoute.parentRefs | list | `[{"name":"kgateway","namespace":"kgateway-system"}]` | Gateways this route attaches to. At least one parent, or the route is inert. |
| httpRoute.pathPrefix | string | `"/"` | Path prefix this route matches. The service owns its whole prefix; per-endpoint routing is the application's business, not the gateway's. |
| image | object | `{"pullPolicy":"IfNotPresent","pullSecrets":[],"repository":"ghcr.io/atomicloud/diene.dotnet-api/diene-dotnet-api","tag":""}` | The one artifact this service ships. `server` and `db-init` are the same image with different args (App/StartUp/RunMode.cs). |
| image.pullPolicy | string | `"IfNotPresent"` | Image pull policy. |
| image.pullSecrets | list | `[]` | Optional image pull secrets. |
| image.repository | string | `"ghcr.io/atomicloud/diene.dotnet-api/diene-dotnet-api"` | Image repository. Never `:latest` — the tag is a pin (M25). |
| image.tag | string | `""` | Image tag. EMPTY falls back to the chart `appVersion`, which is the one semver the `chart-versions` gate holds equal across the image and both charts. |
| labelPrefix | string | `"atomi.cloud"` | Prefix used by every service-tree label and annotation helper. One configurable key (R16/B26) — never hard-coded inside a helper. |
| podSecurityContext | object | `{"fsGroup":1654,"runAsGroup":1654,"runAsNonRoot":true,"runAsUser":1654,"seccompProfile":{"type":"RuntimeDefault"}}` | Pod-level security context. The chiseled base runs as uid/gid 1654 (`$APP_UID`), so a different uid here would fail to read the published assets. |
| secret | object | `{"apiVersion":"external-secrets.io/v1","enabled":true,"refreshInterval":"1h","serviceFolder":"/dotnet-api","sharedFolder":"/shared","store":{"kind":"SecretStore","name":"platform-store"},"syncWave":"-2"}` | One service-scoped ExternalSecret materializing this service's secret from the platform SecretStore. The service ASSUMES the store already exists — carbon creates exactly one per platform through the SoS chain. There is no `sulfoxide-bromine:` values key and no PushSecret (B12): this chart only ever READS. |
| secret.apiVersion | string | `"external-secrets.io/v1"` | API group/version of the External Secrets Operator CRs. |
| secret.enabled | bool | `true` | Render the ExternalSecret. |
| secret.refreshInterval | string | `"1h"` | ESO refresh cadence. |
| secret.serviceFolder | string | `"/dotnet-api"` | This service's own folder, fanned in with a `DOTNET_API_` key prefix (B9d) — the service name upper-cased with every non-alphanumeric run folded to `_`, so the result is always a legal environment-variable name. |
| secret.sharedFolder | string | `"/shared"` | Shared platform folder, fanned in with a `SHARED_` key prefix (B9d). |
| secret.store.kind | string | `"SecretStore"` | The platform SecretStore is namespace-scoped (created by carbon). |
| secret.store.name | string | `"platform-store"` | Platform SecretStore name. |
| secret.syncWave | string | `"-2"` | Sync wave. Secrets land before db-init and before the rollout. |
| service | object | `{"annotations":{},"enabled":true,"port":80,"portName":"http","type":"ClusterIP"}` | ClusterIP Service fronting the Deployment. The HTTPRoute is what exposes it. |
| service.annotations | object | `{}` | Extra annotations for the Service. |
| service.enabled | bool | `true` | Render the Service. |
| service.port | int | `80` | Port the Service listens on. |
| service.portName | string | `"http"` | Named port the HTTPRoute and the Service target. |
| service.type | string | `"ClusterIP"` | Service type. Edge exposure is the gateway's job, so ClusterIP is the only shape this chart is designed around. |
| serviceTree | object | `{"landscape":"lapras","layer":"2","module":"api","platform":"sulfoxide","service":"dotnet-api"}` | Stable service-tree projection (LPSM, docs/standards/service-tree). Also projected into both workloads as `ATOMI_APP__*` so the Kubernetes labels and the telemetry resource attributes cannot disagree — alert routing matches on these exact values. |
| serviceTree.landscape | string | `"lapras"` | Landscape. The ONLY overlay axis (R16 — there is no cluster axis in a service repo). Also projected as the `LANDSCAPE` variable, which is what selects `Config/settings.<landscape>.yaml` inside the container. |
| serviceTree.layer | string | `"2"` | Architecture layer (application tier). |
| serviceTree.module | string | `"api"` | Module name for this workload. |
| serviceTree.platform | string | `"sulfoxide"` | Platform name (functional group). Matches `app.platform` in `App/Config/settings.yaml`. |
| serviceTree.service | string | `"dotnet-api"` | Service name. The REAL identity (R4): it is what `App/Config/settings.yaml` declares, what `problems:export` stamps into every minted type URI, and what alert routing matches on. Every resource this chart owns is named `<service>-<token>`. |
| shutdown | object | `{"terminationGracePeriodSeconds":45,"timeoutSeconds":30}` | Graceful shutdown, aligned end to end. `timeoutSeconds` is projected as `ASPNETCORE_SHUTDOWNTIMEOUTSECONDS`, so the host's own drain budget and the kubelet's grace period come from ONE number instead of two that quietly disagree. `_helpers.tpl` FAILS the render when the grace period is not strictly greater than the shutdown timeout — a pod that is SIGKILLed while still draining is a dropped in-flight request. |
| shutdown.terminationGracePeriodSeconds | int | `45` | Seconds the kubelet waits after SIGTERM before SIGKILL. Must exceed `timeoutSeconds`. |
| shutdown.timeoutSeconds | int | `30` | Seconds ASP.NET Core waits for in-flight requests before completing shutdown. |
