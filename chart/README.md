# diene-chlorine

![Version: 0.1.0](https://img.shields.io/badge/Version-0.1.0-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square) ![AppVersion: v1.4.19](https://img.shields.io/badge/AppVersion-v1.4.19-informational?style=flat-square)

Pure passthrough Stakater Reloader wrapper chart for AtomiCloud platform landscapes

## Requirements

Kubernetes: `>=1.22.0-0`

| Repository | Name | Version |
|------------|------|---------|
| https://stakater.github.io/stakater-charts | reloader | 2.2.14 |

## What chlorine owns (and does not)

chlorine is a **pure passthrough** wrapper over the upstream
[`stakater/reloader`](https://github.com/stakater/Reloader) controller. It is the
last hop of the secret-rotation chain (Infisical rotate → ESO sync → **Reloader
restart**): when a workload's referenced Secret/ConfigMap changes, Reloader
rolling-restarts that workload's pods.

It is the SIMPLEST wrapper instance — the parity check that the helm-wrapper
template needs zero bespoke additions. The chart renders one controller
Deployment plus its RBAC (no CRDs, webhook, or cainjector). The wrapper carries
only minimal upstream overrides:

- `reloader.image.tag` pinned to the chart appVersion (VAP forbids `:latest`).
- `reloader.reloader.autoReloadAll: false` — Reloader is **annotation opt-in**,
  never auto-reload-all. Only workloads carrying `reloader.stakater.com/auto:
  "true"` are restarted; the helm-wrapper bakes that opt-in into every family
  chart by default (omitted only for stateful/unsafe workloads).
- resource envelopes and baseline-plus container hardening so the shared VAP
  profile passes.
- the Reloader opt-in annotation on chlorine's own controller Deployment.

## Identity and labels

reloader has no `global.commonLabels` passthrough, so the static service-tree
labels ride the chart's own `reloader.deployment.labels` override onto the
controller Deployment and pod. The namespace-sourced platform label cannot be a
static value, so the wrapper-owned `chlorine-lpsm` ConfigMap carries the full
dynamic LPSM projection (platform = release namespace, plus the
landscape/service/module/layer slots and reversible physical-instance
annotations). `global.serviceTree.platform` is forbidden as a value — platform
always comes from the release namespace.

## Upstream selection

The vendored dependency is official reloader chart `2.2.14` / app `v1.4.19`,
pinned pure-passthrough from the recorded source archive hash in
`chart/upstream-evidence.yaml` (the current official latest). `pls latest` checks
the official chart repository and the `ghcr.io/stakater` image registry against
the recorded evidence.

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| global | object | `{"instance":{"physicalId":"example-repository:run-001"},"labelPrefix":"atomi.cloud","serviceTree":{"layer":"1","module":"reloader","service":"chlorine"}}` | Values shared with the vendored reloader dependency through Helm's supported parent-to-subchart global-values contract. |
| global.instance | object | `{"physicalId":"example-repository:run-001"}` | Optional physical-instance metadata. The instance remains outside LPSM. |
| global.instance.physicalId | string | `"example-repository:run-001"` | Repository-qualified physical instance id. |
| global.labelPrefix | string | `"atomi.cloud"` | Single prefix used by every wrapper service-tree label and annotation helper. |
| global.serviceTree | object | `{"layer":"1","module":"reloader","service":"chlorine"}` | Stable service-tree projection. Platform is always the release namespace; landscape and cluster are added by independent overlays. |
| global.serviceTree.layer | string | `"1"` | Architecture layer. |
| global.serviceTree.module | string | `"reloader"` | Module name. |
| global.serviceTree.service | string | `"chlorine"` | Service name. |
| reloader | object | `{"fullnameOverride":"chlorine-reloader","image":{"tag":"v1.4.19"},"nameOverride":"reloader","reloader":{"autoReloadAll":false,"deployment":{"annotations":{"reloader.stakater.com/auto":"true"},"containerSecurityContext":{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]},"readOnlyRootFilesystem":true,"runAsNonRoot":true},"labels":{"atomi.cloud/layer":"1","atomi.cloud/module":"reloader","atomi.cloud/service":"chlorine"},"replicas":1,"resources":{"limits":{"cpu":"100m","memory":"128Mi"},"requests":{"cpu":"10m","memory":"32Mi"}}},"reloadStrategy":"default"}}` | Pure passthrough of the vendored stakater/reloader engine. Reloader is the last hop of the secret-rotation chain (Infisical rotate → ESO sync → Reloader restart): it restarts a workload only when a Secret/ConfigMap the workload references changes. This map carries only the minimal upstream overrides: canonical names, the pinned image tag, the annotation-opt-in reload stance, resource envelopes, container hardening, and the Reloader self opt-in. |
| reloader.image | object | `{"tag":"v1.4.19"}` | Pin the controller image to the chart appVersion (VAP forbids `:latest`). |
| reloader.nameOverride | string | `"reloader"` | Pin the canonical `chlorine-reloader` object names (fullname convention: `<service>-<token>`, exactly one dash). `nameOverride` fixes the chart-name derived identifiers (app labels, container name); `fullnameOverride` fixes the rendered object names. |
| reloader.reloader | object | `{"autoReloadAll":false,"deployment":{"annotations":{"reloader.stakater.com/auto":"true"},"containerSecurityContext":{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]},"readOnlyRootFilesystem":true,"runAsNonRoot":true},"labels":{"atomi.cloud/layer":"1","atomi.cloud/module":"reloader","atomi.cloud/service":"chlorine"},"replicas":1,"resources":{"limits":{"cpu":"100m","memory":"128Mi"},"requests":{"cpu":"10m","memory":"32Mi"}}},"reloadStrategy":"default"}` | Upstream reloader controller configuration. |
| reloader.reloader.autoReloadAll | bool | `false` | Annotation OPT-IN, never auto-reload-all. Reloader restarts only the workloads that carry `reloader.stakater.com/auto: "true"` (the opt-in the helm-wrapper bakes into every family chart by default). Flipping this to true would reload EVERY workload unless it opts out — the fleet convention is the opposite, so it stays false. |
| reloader.reloader.deployment.annotations | object | `{"reloader.stakater.com/auto":"true"}` | Reloader opt-in on its own controller Deployment; restarts on config change like every other family chart. |
| reloader.reloader.deployment.containerSecurityContext | object | `{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]},"readOnlyRootFilesystem":true,"runAsNonRoot":true}` | Baseline-plus container hardening (upstream leaves the container securityContext empty; the shared VAP profile requires non-root, no privilege escalation, a read-only root filesystem, and all caps dropped). |
| reloader.reloader.deployment.labels | object | `{"atomi.cloud/layer":"1","atomi.cloud/module":"reloader","atomi.cloud/service":"chlorine"}` | Static service-tree labels projected onto the controller Deployment and pod (reloader has no `global.commonLabels` passthrough, so the projection rides the chart's own deployment-label override). Keys stay consistent with `global.serviceTree`; overlays append the landscape label. The namespace-sourced platform label cannot be a static value, so the wrapper-owned LPSM ConfigMap carries the full dynamic LPSM projection. |
| reloader.reloader.deployment.replicas | int | `1` | Single controller replica; leadership election is off (enableHA: false), so one active instance is the generic default. |
| reloader.reloader.deployment.resources | object | `{"limits":{"cpu":"100m","memory":"128Mi"},"requests":{"cpu":"10m","memory":"32Mi"}}` | CPU and memory envelopes for the controller container (VAP requires both requests and limits on every workload container). |
| reloader.reloader.reloadStrategy | string | `"default"` | Default reload strategy (rolling restart via a dated pod annotation); the env-vars/annotations strategies are not used. |
