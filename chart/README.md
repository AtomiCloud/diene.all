# diene-xenon

![Version: 0.1.0](https://img.shields.io/badge/Version-0.1.0-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square) ![AppVersion: 0.8.1](https://img.shields.io/badge/AppVersion-0.8.1-informational?style=flat-square)

Conditional metrics-server wrapper chart for AtomiCloud platform landscapes

## Requirements

Kubernetes: `>=1.31.0-0`

| Repository | Name | Version |
|------------|------|---------|
| https://kubernetes-sigs.github.io/metrics-server | metricsServer(metrics-server) | 3.13.1 |

## Per-cloud needed/provided matrix

xenon is the resource metrics API (HPA + `kubectl top`). The whole chart is gated
by `metricsServer.enabled` per landscape — **ON** where the managed offering lacks
metrics-server, **OFF** only where the substrate bundles it.

| Provider | Named landscapes | metrics-server preinstalled? | xenon enabled | kubelet TLS |
|----------|------------------|------------------------------|---------------|-------------|
| EKS classic | pichu, pikachu, raichu | no (the community add-on is opt-in) | ON | secure |
| EKS Auto Mode | pichu, pikachu, raichu | no (built-ins do not include metrics-server) | ON | secure |
| DOKS | pichu, pikachu, raichu | no (Marketplace 1-click is user-managed) | ON | secure |
| on-prem | onprem | no | ON | cluster overlay may supply kubelet args |
| k3s / k3d | lapras | yes (k3s bundles it; disable via `--disable metrics-server`) | OFF | bundled |

The chart stays installable on every landscape; flipping it OFF renders no
resources. The k3d/insecure-TLS posture is an overlay decision, not a baseline
default — secure TLS is shipped for cloud/on-prem.

## Enablement toggle map

`chart/toggle-map.yaml` is the authoritative provider × named-landscape map.
The unit gate renders every referenced committed stack and compares actual
resource presence with both expectations; its lapras OFF→ON mutation runs the
same checker. See
[docs/developer/xenon-baseline.md](../docs/developer/xenon-baseline.md) for the
full conditional-enablement contract.

## Upstream selection

The vendored dependency is official metrics-server chart `3.13.1` / app
`0.8.1`, with the wrapper integration applied reproducibly from the pinned
source archive. `chart/upstream-evidence.yaml` records source and patched hashes,
the latest-repository check, and why image `v0.9.0` is not selected (no released
chart and Kubernetes 1.34+ versus this chart's 1.31 floor).

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| global | object | `{"instance":{"physicalId":"example-repository:run-001"},"labelPrefix":"atomi.cloud","serviceTree":{"layer":"1","module":"metrics","service":"xenon"}}` | Values shared with the vendored metrics-server dependency through Helm's supported parent-to-subchart global-values contract. |
| global.instance | object | `{"physicalId":"example-repository:run-001"}` | Optional physical-instance metadata. The instance remains outside LPSM. |
| global.instance.physicalId | string | `"example-repository:run-001"` | Repository-qualified physical instance id. |
| global.labelPrefix | string | `"atomi.cloud"` | Single prefix used by every service-tree label and annotation helper. |
| global.serviceTree | object | `{"layer":"1","module":"metrics","service":"xenon"}` | Stable service-tree projection. Platform is always the release namespace; landscape and cluster are added by independent overlays. |
| global.serviceTree.layer | string | `"1"` | Architecture layer. |
| global.serviceTree.module | string | `"metrics"` | Module name. |
| global.serviceTree.service | string | `"xenon"` | Service name. |
| metricsServer | object | `{"args":[],"enabled":true,"fullnameOverride":"xenon-metrics","podAnnotations":{"reloader.stakater.com/auto":"true"},"podSecurityContext":{"fsGroup":1000,"runAsGroup":1000,"runAsNonRoot":true,"runAsUser":1000},"replicas":2,"resources":{"limits":{"cpu":"200m","memory":"256Mi"},"requests":{"cpu":"50m","memory":"64Mi"}}}` | Per-landscape enablement toggle and the vendored metrics-server chart inputs. The whole chart is gated by `metricsServer.enabled`: it defaults ON here for every cloud and on-prem landscape (EKS classic/Auto, DOKS, and on-prem do not preinstall metrics-server) and is flipped OFF only by the k3d/lapras overlay, because k3s bundles metrics-server. Final per-profile ENV roster entries stay outside this node. |
| metricsServer.args | list | `[]` | Kubelet scrape arguments. Secure TLS is the cloud/on-prem default; the k3d/insecure posture is an overlay decision documented in the README matrix. |
| metricsServer.enabled | bool | `true` | Per-landscape toggle. ON for cloud/on-prem, OFF for k3d/lapras. |
| metricsServer.fullnameOverride | string | `"xenon-metrics"` | Conforming metrics-server fullname (`<service>-<dashless-token>`). |
| metricsServer.podAnnotations | object | `{"reloader.stakater.com/auto":"true"}` | Reloader opt-in on the metrics-server pod. The vendored integration patch independently projects the global service-tree metadata onto the Deployment and pod; this map retains only the upstream-supported opt-out surface. |
| metricsServer.podSecurityContext | object | `{"fsGroup":1000,"runAsGroup":1000,"runAsNonRoot":true,"runAsUser":1000}` | Pod-level security context satisfying the baseline-plus VAP policy. |
| metricsServer.replicas | int | `2` | Highly available replica count for managed-cloud deployments. |
| metricsServer.resources | object | `{"limits":{"cpu":"200m","memory":"256Mi"},"requests":{"cpu":"50m","memory":"64Mi"}}` | CPU and memory envelopes for the metrics-server container. |
