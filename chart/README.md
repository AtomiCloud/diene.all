# diene-charts-aluminium

![Version: 0.1.0](https://img.shields.io/badge/Version-0.1.0-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square) ![AppVersion: 4.3.0](https://img.shields.io/badge/AppVersion-4.3.0-informational?style=flat-square)

AtomiCloud wrapper around grafana/k8s-monitoring (Alloy Operator + alloy-metrics StatefulSet + alloy-logs DaemonSet)

## Requirements

Kubernetes: `>=1.27.0-0`

| Repository | Name | Version |
|------------|------|---------|
| https://grafana.github.io/helm-charts | upstream(k8s-monitoring) | 4.3.0 |

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| labelPrefix | string | `"atomi.cloud"` |  |
| secret.enabled | bool | `false` |  |
| secret.refreshInterval | string | `"1h"` |  |
| secret.serviceFolder | string | `"/svc/aluminium"` |  |
| secret.sharedFolder | string | `"/shared/aluminium"` |  |
| secret.store.kind | string | `"ClusterSecretStore"` |  |
| secret.store.name | string | `"platform-secret-store"` |  |
| serviceTree.layer | string | `"1"` |  |
| serviceTree.module | string | `"telemetry"` |  |
| serviceTree.platform | string | `"telemetry"` |  |
| serviceTree.service | string | `"aluminium"` |  |
| upstream.alloy-operator.deploy | bool | `true` |  |
| upstream.applicationObservability.collector | string | `"alloy-metrics"` |  |
| upstream.applicationObservability.destinations[0] | string | `"victoriametrics"` |  |
| upstream.applicationObservability.destinations[1] | string | `"gigapipe"` |  |
| upstream.applicationObservability.enabled | bool | `true` |  |
| upstream.applicationObservability.receivers.otlp.grpc.enabled | bool | `false` |  |
| upstream.applicationObservability.receivers.otlp.http.enabled | bool | `true` |  |
| upstream.applicationObservability.receivers.otlp.http.port | int | `4318` |  |
| upstream.cluster.name | string | `"local"` |  |
| upstream.clusterMetrics.collector | string | `"alloy-metrics"` |  |
| upstream.clusterMetrics.enabled | bool | `true` |  |
| upstream.collectors.alloy-logs.alloy.labels."atomi.cloud/layer" | string | `"1"` |  |
| upstream.collectors.alloy-logs.alloy.labels."atomi.cloud/module" | string | `"telemetry"` |  |
| upstream.collectors.alloy-logs.alloy.labels."atomi.cloud/platform" | string | `"telemetry"` |  |
| upstream.collectors.alloy-logs.alloy.labels."atomi.cloud/service" | string | `"aluminium"` |  |
| upstream.collectors.alloy-logs.alloy.mounts.varlog | bool | `true` |  |
| upstream.collectors.alloy-logs.alloy.resources.limits.cpu | string | `"250m"` |  |
| upstream.collectors.alloy-logs.alloy.resources.limits.memory | string | `"256Mi"` |  |
| upstream.collectors.alloy-logs.alloy.resources.requests.cpu | string | `"50m"` |  |
| upstream.collectors.alloy-logs.alloy.resources.requests.memory | string | `"64Mi"` |  |
| upstream.collectors.alloy-logs.alloy.stabilityLevel | string | `"public-preview"` |  |
| upstream.collectors.alloy-logs.controller.type | string | `"daemonset"` |  |
| upstream.collectors.alloy-metrics.alloy.clustering.enabled | bool | `true` |  |
| upstream.collectors.alloy-metrics.alloy.labels."atomi.cloud/layer" | string | `"1"` |  |
| upstream.collectors.alloy-metrics.alloy.labels."atomi.cloud/module" | string | `"telemetry"` |  |
| upstream.collectors.alloy-metrics.alloy.labels."atomi.cloud/platform" | string | `"telemetry"` |  |
| upstream.collectors.alloy-metrics.alloy.labels."atomi.cloud/service" | string | `"aluminium"` |  |
| upstream.collectors.alloy-metrics.alloy.resources.limits.cpu | string | `"500m"` |  |
| upstream.collectors.alloy-metrics.alloy.resources.limits.memory | string | `"512Mi"` |  |
| upstream.collectors.alloy-metrics.alloy.resources.requests.cpu | string | `"100m"` |  |
| upstream.collectors.alloy-metrics.alloy.resources.requests.memory | string | `"128Mi"` |  |
| upstream.collectors.alloy-metrics.controller.replicas | int | `1` |  |
| upstream.collectors.alloy-metrics.controller.type | string | `"statefulset"` |  |
| upstream.destinations.gigapipe.auth.type | string | `"none"` |  |
| upstream.destinations.gigapipe.logs.enabled | bool | `true` |  |
| upstream.destinations.gigapipe.metrics.enabled | bool | `false` |  |
| upstream.destinations.gigapipe.protocol | string | `"http"` |  |
| upstream.destinations.gigapipe.traces.enabled | bool | `true` |  |
| upstream.destinations.gigapipe.type | string | `"otlp"` |  |
| upstream.destinations.gigapipe.url | string | `"http://gigapipe:4318"` |  |
| upstream.destinations.victoriametrics.auth.type | string | `"none"` |  |
| upstream.destinations.victoriametrics.logs.enabled | bool | `false` |  |
| upstream.destinations.victoriametrics.metrics.enabled | bool | `true` |  |
| upstream.destinations.victoriametrics.protocol | string | `"http"` |  |
| upstream.destinations.victoriametrics.traces.enabled | bool | `false` |  |
| upstream.destinations.victoriametrics.type | string | `"otlp"` |  |
| upstream.destinations.victoriametrics.url | string | `"http://victoriametrics:4318"` |  |
| upstream.podLogsViaOpenTelemetry.collector | string | `"alloy-logs"` |  |
| upstream.podLogsViaOpenTelemetry.destinations[0] | string | `"gigapipe"` |  |
| upstream.podLogsViaOpenTelemetry.enabled | bool | `true` |  |
| upstream.telemetryServices.kube-state-metrics.deploy | bool | `true` |  |
| upstream.telemetryServices.node-exporter.deploy | bool | `true` |  |

----------------------------------------------
Autogenerated from chart metadata using [helm-docs v1.14.2](https://github.com/norwoodj/helm-docs/releases/v1.14.2)
