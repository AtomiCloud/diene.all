# diene-xenon

![Version: 0.1.0](https://img.shields.io/badge/Version-0.1.0-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square) ![AppVersion: 0.7.1](https://img.shields.io/badge/AppVersion-0.7.1-informational?style=flat-square)

Conditional metrics-server wrapper chart for AtomiCloud platform landscapes

## Requirements

Kubernetes: `>=1.27.0-0`

| Repository | Name | Version |
|------------|------|---------|
| https://kubernetes-sigs.github.io/metrics-server | metricsServer(metrics-server) | 3.12.1 |

## Per-cloud needed/provided matrix

xenon is the resource metrics API (HPA + `kubectl top`). The whole chart is gated
by `metricsServer.enabled` per landscape — **ON** where the managed offering lacks
metrics-server, **OFF** only where the substrate bundles it.

| Cloud | metrics-server preinstalled? | xenon enabled | kubelet TLS |
|-------|------------------------------|---------------|-------------|
| EKS classic | no (AtomiCloud clusters are T3/API-created; the community add-on is opt-in only) | ON | secure |
| EKS Auto Mode | no (built-ins do not include metrics-server) | ON | secure |
| DOKS | no (Marketplace 1-click is user-managed only) | ON | secure |
| on-prem | no | ON | overlay (per-cluster kubelet TLS args) |
| k3d / lapras | yes (k3s bundles it; disable via `--disable metrics-server`) | OFF | bundled |

The chart stays installable on every landscape; flipping it OFF renders no
resources. The k3d/insecure-TLS posture is an overlay decision, not a baseline
default — secure TLS is shipped for cloud/on-prem.

## Enablement toggle map

`chart/toggle-map.yaml` is the source of truth for the unit-tier toggle gate:
each committed overlay is rendered against `values.yaml` and its actual
enablement is compared to the declared value. See
[docs/developer/xenon-baseline.md](../docs/developer/xenon-baseline.md) for the
full conditional-enablement contract.

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| instance | object | `{"physicalId":"example-repository:run-001"}` | Optional physical-instance metadata. The instance remains outside LPSM. |
| labelPrefix | string | `"atomi.cloud"` | Prefix used by every service-tree label and annotation helper. |
| metricsServer | object | `{"args":[],"enabled":true,"fullnameOverride":"xenon-metrics","podAnnotations":{"atomi.cloud/module":"metrics","atomi.cloud/platform":"sample","atomi.cloud/service":"xenon","reloader.stakater.com/auto":"true"},"podLabels":{"atomi.cloud/layer":"1","atomi.cloud/module":"metrics","atomi.cloud/platform":"sample","atomi.cloud/service":"xenon"},"podSecurityContext":{"fsGroup":1000,"runAsGroup":1000,"runAsNonRoot":true,"runAsUser":1000},"replicas":2,"resources":{"limits":{"cpu":"200m","memory":"256Mi"},"requests":{"cpu":"50m","memory":"64Mi"}}}` | Per-landscape enablement toggle and the vendored metrics-server chart inputs. The whole chart is gated by `metricsServer.enabled`: it defaults ON here for every cloud and on-prem landscape (EKS classic/Auto, DOKS, and on-prem do not preinstall metrics-server) and is flipped OFF only by the k3d/lapras overlay, because k3s bundles metrics-server. Final per-profile ENV roster entries stay outside this node. |
| metricsServer.args | list | `[]` | Kubelet scrape arguments. Secure TLS is the cloud/on-prem default; the k3d/insecure posture is an overlay decision documented in the README matrix. |
| metricsServer.enabled | bool | `true` | Per-landscape toggle. ON for cloud/on-prem, OFF for k3d/lapras. |
| metricsServer.fullnameOverride | string | `"xenon-metrics"` | Conforming metrics-server fullname (`<service>-<dashless-token>`). |
| metricsServer.podAnnotations | object | `{"atomi.cloud/module":"metrics","atomi.cloud/platform":"sample","atomi.cloud/service":"xenon","reloader.stakater.com/auto":"true"}` | Reloader opt-in plus service-tree annotations on the metrics-server pod. Reloader is opt-in at the controller and baked ON here by the wrapper. Because the annotation reaches the pod through the metrics-server subchart's `podAnnotations` map (Helm coalesces subchart values and cannot drop a single key), a stateful/unsafe landscape opts out by overriding the value to 'false' — Reloader only reloads on the literal 'true', so any other value opts out. |
| metricsServer.podLabels | object | `{"atomi.cloud/layer":"1","atomi.cloud/module":"metrics","atomi.cloud/platform":"sample","atomi.cloud/service":"xenon"}` | Service-tree identity stamped onto the metrics-server pod. |
| metricsServer.podSecurityContext | object | `{"fsGroup":1000,"runAsGroup":1000,"runAsNonRoot":true,"runAsUser":1000}` | Pod-level security context satisfying the baseline-plus VAP policy. |
| metricsServer.replicas | int | `2` | Highly available replica count for managed-cloud deployments. |
| metricsServer.resources | object | `{"limits":{"cpu":"200m","memory":"256Mi"},"requests":{"cpu":"50m","memory":"64Mi"}}` | CPU and memory envelopes for the metrics-server container. |
| serviceTree | object | `{"layer":"1","module":"metrics","platform":"sample","service":"xenon"}` | Stable four-slot service-tree projection. Landscape and cluster are added by independent overlays. |
