# diene-bunconsumer

![Version: 0.1.0](https://img.shields.io/badge/Version-0.1.0-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square) ![AppVersion: 0.1.0](https://img.shields.io/badge/AppVersion-0.1.0-informational?style=flat-square)

Runtime app chart for the diene bun-consumer worker — worker Deployment with dependency-blind exec probes, db-init pre-sync Job, ExternalSecret, and the vendored config ConfigMap

## What this chart owns (and does not)

This is the **app chart** half of the R20 two-chart model. It is pure runtime and
deploys to application/landscape clusters:

| Resource                                                | Why                                                                   |
| ------------------------------------------------------- | --------------------------------------------------------------------- |
| `Deployment` `bunconsumer-worker`                       | the long-running consume/produce loop                                 |
| `Job` `bunconsumer-dbinit`                              | one-shot pre-sync migration/seed entry point                          |
| `ConfigMap` `bunconsumer-config` / `-dbinitconfig`      | the vendored application config YAMLs                                 |
| `ExternalSecret` `bunconsumer-secrets`                  | materializes the service secret from the platform SecretStore         |

It owns **no `Service` and no `HTTPRoute`** — the consumer serves no HTTP.
Telemetry is push-based OTLP, so there is no `/metrics` scrape surface either.
It owns **no cron surface** (Q10: one-shot Jobs are the only sanctioned job
shape) and **no dependency sub-charts** (B30.5) — postgres, KV, cache, and object
storage are requested through the sibling
[primordial chart](../primordial_chart/README.md)'s CRs in **every** landscape,
including lapras.

## Dependency-blind probes (DQ16 / R20)

Liveness **and** readiness are `exec` probes running the binary's `health`
subcommand through the same artifact the image entrypoint runs
(`bun dist/index.js health`). `health` inspects worker heartbeat and internal
state only. A postgres/redis/S3 blip must degrade the service, never evict every
pod. Dependency reachability belongs to `db-init` and to alerting.

## db-init ordering, and why the rollout stays a rolling update

`bunconsumer-dbinit` carries **both** hook systems — helm
`pre-install,pre-upgrade` and ArgoCD `PreSync` — plus
`hook-delete-policy: before-hook-creation` so a re-run is not an
immutable-field conflict. Sync waves order it after the secret/config and ahead
of the Deployment's implicit wave 0.

The Job's checksum is deliberately **not** coupled into the Deployment's pod
template. A migration must never trigger full app recreation; the Deployment
always performs a normal `RollingUpdate`.

Because helm hooks and ArgoCD PreSync both run before the release's ordinary
resources, the Job mounts its **own** hook-scoped copy of the config ConfigMap.
The Deployment's release-scoped copy does not exist yet at that point.

On a **first** install the ExternalSecret has not materialized its target Secret
when the pre-sync Job runs, so the secret `envFrom` is `optional: true` and
db-init must be re-runnable. It is: the seed loader is idempotent
(seed-if-not-exists) and safe for both tests and production.

## Build-phase config vendoring (B30.3)

The application config YAMLs (`config/settings.yaml` plus the landscape overlays)
live **outside** the chart — the app reads them directly in local dev. Helm cannot
reference files outside the chart directory, so the helm **build** step copies
them into `infra/root_chart/files/config/`:

```sh
mkdir -p infra/root_chart/files/config && cp config/*.yaml infra/root_chart/files/config/
```

That directory is **gitignored and never committed** — it is regenerated per
build. Every template guards the copy with `.Files.Glob`, so `helm lint`,
`helm template`, and `helm install` all stay green with zero optional files
present.

When the copy has **not** run, the chart renders **no ConfigMap and no mount at
all** — deliberately, not as a degraded fallback. The image bakes `config/` in at
this same mount path, so mounting an empty ConfigMap would shadow those defaults
with an empty directory. No files copied means the image's own config stays
visible; files copied means the chart-supplied config wins.

## Values overlays

Two **independent stacked** dimensions (R16/B26), never a cross-product:

```sh
helm upgrade --install bunconsumer infra/root_chart \
  -f infra/root_chart/values.yaml \
  -f infra/root_chart/values.lapras.yaml \
  -f infra/root_chart/values.<cluster>.yaml   # thin: usually just the cluster anchor
```

`values.example.yaml` is illustrative caller input, not an overlay dimension.

## Identity

Every resource name is `<service>-<token>` with **exactly one dash** and a
dash-less token (B30.4): `bunconsumer-worker`, `bunconsumer-dbinit`,
`bunconsumer-config`, `bunconsumer-secrets`. All submodules share one service
secret, named after the **service**. LPSM labels and annotations are projected by
`_helpers.tpl` range loops through the single configurable `labelPrefix` key.

## Requirements

Kubernetes: `>=1.27.0-0`

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| config | object | `{"enabled":true,"mountPath":"/app/config","path":"files/config","syncWave":"-2"}` | Application config YAMLs bundled as a ConfigMap. The files live OUTSIDE the chart in local dev (`config/`); the helm BUILD step copies them into `infra/root_chart/files/config/` (GITIGNORED vendoring, B30.3 — never committed). Rendering tolerates the directory being absent so lint/template stay green before the copy runs. |
| config.enabled | bool | `true` | Render the config ConfigMap and mount it into both workloads. |
| config.mountPath | string | `"/app/config"` | Mount path inside the container. Matches the image WORKDIR layout. |
| config.path | string | `"files/config"` | Glob root, relative to the chart directory, for the vendored YAMLs. |
| config.syncWave | string | `"-2"` | Sync wave. Config lands with the secret, before db-init. |
| containerSecurityContext | object | `{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]},"readOnlyRootFilesystem":true}` | Container-level security context shared by the worker and db-init containers. |
| dbInit | object | `{"activeDeadlineSeconds":600,"args":["db-init"],"backoffLimit":3,"enabled":true,"env":[],"resources":{"limits":{"memory":"256Mi"},"requests":{"cpu":"50m","memory":"128Mi"}},"syncWave":"-1","ttlSecondsAfterFinished":300}` | One-shot db-init entry point (B30.2). Runs as a helm `pre-install,pre-upgrade` hook AND an ArgoCD `PreSync` hook, ordered ahead of the Deployment. Its checksum is deliberately NOT coupled into the Deployment: migrations must never trigger a full app recreation. |
| dbInit.activeDeadlineSeconds | int | `600` | Hard wall-clock ceiling for one db-init run. |
| dbInit.args | list | `["db-init"]` | Subcommand appended to the image entrypoint. |
| dbInit.backoffLimit | int | `3` | Job retry budget before the pre-sync hook is declared failed. |
| dbInit.enabled | bool | `true` | Render the db-init hook Job. |
| dbInit.env | list | `[]` | Extra environment variables for the db-init pod only. |
| dbInit.resources | object | `{"limits":{"memory":"256Mi"},"requests":{"cpu":"50m","memory":"128Mi"}}` | db-init resource requests and limits. |
| dbInit.syncWave | string | `"-1"` | Sync wave. Must be greater than `secret.syncWave` and less than the Deployment's implicit wave 0. |
| dbInit.ttlSecondsAfterFinished | int | `300` | Seconds the completed Job is retained for inspection. |
| health | object | `{"command":["bun","dist/index.js","health"],"liveness":{"failureThreshold":3,"initialDelaySeconds":15,"periodSeconds":30,"timeoutSeconds":5},"readiness":{"failureThreshold":3,"initialDelaySeconds":5,"periodSeconds":10,"timeoutSeconds":5}}` | Dependency-blind liveness and readiness (DQ16/R20). BOTH probes exec the binary's `health` subcommand, which inspects worker heartbeat and internal state only — never postgres/redis/S3 reachability. |
| health.command | list | `["bun","dist/index.js","health"]` | Exec command. Must invoke the health subcommand through the same artifact the Dockerfile entrypoint runs. |
| health.liveness.failureThreshold | int | `3` | Consecutive failures before the kubelet restarts the container. |
| health.liveness.initialDelaySeconds | int | `15` | Seconds before the first liveness exec. |
| health.liveness.periodSeconds | int | `30` | Liveness exec interval. |
| health.liveness.timeoutSeconds | int | `5` | Liveness exec timeout. |
| health.readiness.failureThreshold | int | `3` | Consecutive failures before the pod is marked not-ready. |
| health.readiness.initialDelaySeconds | int | `5` | Seconds before the first readiness exec. |
| health.readiness.periodSeconds | int | `10` | Readiness exec interval. |
| health.readiness.timeoutSeconds | int | `5` | Readiness exec timeout. |
| image | object | `{"pullPolicy":"IfNotPresent","pullSecrets":[],"repository":"ghcr.io/atomicloud/diene.bun-consumer","tag":""}` | Worker container image. The artifact's entrypoint is `bun dist/index.js`; the subcommand is supplied per workload through `worker.args` / `dbInit.args`. |
| image.pullPolicy | string | `"IfNotPresent"` | Image pull policy. |
| image.pullSecrets | list | `[]` | Optional image pull secrets. |
| image.repository | string | `"ghcr.io/atomicloud/diene.bun-consumer"` | Image repository. Never `:latest` — the tag is a pin (M25). |
| image.tag | string | `""` | Image tag. Empty falls back to the chart `appVersion`, which CD pins to the one shared semver (chart `version` == image tag). |
| labelPrefix | string | `"atomi.cloud"` | Prefix used by every service-tree label and annotation helper. Single configurable key (R16/B26) — never hard-coded inside a helper. |
| podSecurityContext | object | `{"fsGroup":1000,"runAsGroup":1000,"runAsNonRoot":true,"runAsUser":1000,"seccompProfile":{"type":"RuntimeDefault"}}` | Pod-level security context. The image is unprivileged (M26). |
| secret | object | `{"enabled":true,"refreshInterval":"1h","serviceFolder":"/bunconsumer","sharedFolder":"/shared","store":{"kind":"SecretStore","name":"platform-store"},"syncWave":"-2"}` | One service-scoped ExternalSecret materializing this service's secret from the platform SecretStore that carbon creates (R16 — the bromine subchart is dissolved). All submodules share the one service secret. |
| secret.enabled | bool | `true` | Render the ExternalSecret. |
| secret.refreshInterval | string | `"1h"` | ESO refresh cadence. |
| secret.serviceFolder | string | `"/bunconsumer"` | Service-folder path fanned in with a `BUNCONSUMER_` prefix. |
| secret.sharedFolder | string | `"/shared"` | Shared-folder path fanned in with a `SHARED_` prefix (B9d). |
| secret.store.kind | string | `"SecretStore"` | The platform SecretStore is namespace-scoped (created by carbon). |
| secret.store.name | string | `"platform-store"` | Platform SecretStore name. |
| secret.syncWave | string | `"-2"` | Sync wave. Secrets land before db-init and before the rollout. |
| serviceTree | object | `{"layer":"2","module":"worker","platform":"diene","service":"bunconsumer"}` | Stable service-tree projection (LPSM). Landscape and cluster slots are added by the two independent overlay dimensions (`values.<landscape>.yaml` then `values.<cluster>.yaml`); the base file never carries them. |
| serviceTree.layer | string | `"2"` | Architecture layer (application tier). |
| serviceTree.module | string | `"worker"` | Module name for this workload. |
| serviceTree.platform | string | `"diene"` | Platform name. |
| serviceTree.service | string | `"bunconsumer"` | Service name. Dash-less: every resource name is `<service>-<token>`. |
| worker | object | `{"args":["worker"],"env":[],"replicas":1,"resources":{"limits":{"memory":"256Mi"},"requests":{"cpu":"50m","memory":"128Mi"}},"rollingUpdate":{"maxSurge":1,"maxUnavailable":0},"terminationGracePeriodSeconds":30}` | The long-running consumer/producer workload. There is NO HTTP surface, so the chart ships no Service and no HTTPRoute. |
| worker.args | list | `["worker"]` | Subcommand appended to the image entrypoint. |
| worker.env | list | `[]` | Extra environment variables (`ATOMI_X__Y` overrides, R14/R21). |
| worker.replicas | int | `1` | Replica count. |
| worker.resources | object | `{"limits":{"memory":"256Mi"},"requests":{"cpu":"50m","memory":"128Mi"}}` | Worker resource requests and limits. |
| worker.rollingUpdate | object | `{"maxSurge":1,"maxUnavailable":0}` | Rolling-update knobs. The db-init hook Job must never force recreation, so `RollingUpdate` is the only supported strategy (R20). |
| worker.rollingUpdate.maxSurge | int | `1` | Maximum surge pods during a rollout. |
| worker.rollingUpdate.maxUnavailable | int | `0` | Maximum unavailable pods during a rollout. |
| worker.terminationGracePeriodSeconds | int | `30` | Grace period for the consumer to finish in-flight messages and ack. |
