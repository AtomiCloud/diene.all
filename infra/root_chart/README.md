# fleet-operator

![Version: 0.1.0](https://img.shields.io/badge/Version-0.1.0-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square) ![AppVersion: 0.1.0](https://img.shields.io/badge/AppVersion-0.1.0-informational?style=flat-square)

Manager chart for the AtomiCloud fleet operator (CRDs, RBAC, deployment, observability)

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| alerts | object | `{"enabled":true,"folderUID":"fleet-operator","tickProducerControllers":[]}` | Grafana alert pack (GrafanaAlertRuleGroup, never PrometheusRule). |
| alerts.enabled | bool | `true` | Ship the GrafanaAlertRuleGroup. |
| alerts.folderUID | string | `"fleet-operator"` | Grafana folder UID the rule group is filed under. |
| alerts.tickProducerControllers | list | `[]` | Controllers explicitly configured as producers of the last-successful-tick TIMESTAMP gauge (`Recorder.MarkTick`). The timestamp-staleness rule pages on no-data by design, so it is rendered ONLY for the controllers listed here — a controller with no writer would otherwise page forever on a deliberately empty series. Empty is the safe default: no staleness rule is shipped at all. Every entry must be a bounded `metricLabels.controllers` value or the render fails. |
| blastBrakeCap | int | `20` | Destructive-write percentage-per-tick blast-brake cap. |
| controllers | object | `{"cf-deploy":false,"cluster":false,"dependency":false,"platform":false,"problem":false,"traffic":false,"webhook":false}` | Per-controller enablement flags. |
| controllers.cf-deploy | bool | `false` | Enable the Cloudflare deployment controller. |
| controllers.cluster | bool | `false` | Enable the cluster controller. |
| controllers.dependency | bool | `false` | Enable the dependency controller. |
| controllers.platform | bool | `false` | Enable the platform controller. |
| controllers.problem | bool | `false` | Enable the reserved Problem sub-component seam. |
| controllers.traffic | bool | `false` | Enable the traffic controller. |
| controllers.webhook | bool | `false` | Enable the webhook controller. |
| dashboard | object | `{"enabled":true}` | Grafana dashboard shipped as a sidecar-labelled ConfigMap. |
| dashboard.enabled | bool | `true` | Ship the dashboard ConfigMap. |
| dependencyDestructiveCapPerTick | int | `3` | Dependency destructive-module cap per tick. |
| image | object | `{"pullPolicy":"IfNotPresent","repository":"ghcr.io/atomicloud/diene.fleet-operator","tag":""}` | Manager container image repository. |
| image.pullPolicy | string | `"IfNotPresent"` | Image pull policy. |
| image.tag | string | `""` | Image tag; defaults to the chart appVersion when empty. |
| ledger | object | `{"bucket":"fleet-operator-ledger","endpoint":"","landscape":"lapras","platform":"diene","secure":true}` | Ledger coordinate scope and S3/MinIO backend. |
| ledger.bucket | string | `"fleet-operator-ledger"` | Ledger bucket name. |
| ledger.endpoint | string | `""` | S3/MinIO endpoint host:port. |
| ledger.landscape | string | `"lapras"` | Landscape coordinate (overridden per landscape values file). |
| ledger.platform | string | `"diene"` | Platform coordinate. |
| ledger.secure | bool | `true` | Use TLS for the ledger endpoint. |
| metricLabels | object | `{"controllers":["cluster","platform","dependency","traffic","webhook","cf-deploy","problem"],"vendors":["cloudflare","neon","aws","infisical","mercury"]}` | Bounded metric label vocabularies. These MIRROR the closed vocabularies `adapters/operator/metrics/metrics.go` enforces at the recorder boundary: a label value outside its vocabulary is recorded as the fixed `other` sentinel, so a chart selector naming an unlisted value could never match a series. They are rendered into the metric-taxonomy ConfigMap and cross-checked against the Go recorder by `scripts/validate/operator-observability-artifacts.ts`. |
| metricLabels.controllers | list | `["cluster","platform","dependency","traffic","webhook","cf-deploy","problem"]` | Closed controller label vocabulary (plus the fixed `other` overflow): the seven real enable seams the runtime declares. `problem` is reserved — its seam is not folded yet, so nothing emits under that label today, but a known future controller must have its own label instead of collapsing into `other` the day its writer lands. |
| metricLabels.vendors | list | `["cloudflare","neon","aws","infisical","mercury"]` | Closed vendor label vocabulary (plus the fixed `other` overflow). The ProviderAccount CRD vendor grammar is deliberately open; this observability vocabulary is not that grammar, and an unlisted vendor is identified from the vendor-call-failure log line instead of by minting a new series. |
| metrics | object | `{"port":8443}` | Secured metrics endpoint configuration. |
| metrics.port | int | `8443` | Metrics bind port (HTTPS, authn/authz filtered). |
| mode | string | `"active"` | Reconcile mode: observe (read-only, report the would-apply plan) or active. |
| replicas | int | `1` | Number of manager replicas. Leader election keeps a single active manager. |
| resources | object | `{"limits":{"cpu":"500m","memory":"256Mi"},"requests":{"cpu":"50m","memory":"64Mi"}}` | Manager resource requests and limits. |
| serviceAccount | object | `{"name":""}` | ServiceAccount name override; defaults to the release fullname. |
| serviceMonitor | object | `{"enabled":true,"interval":"30s","scraper":{"create":true,"externalSecret":{"key":"token","name":""},"serviceAccountName":""}}` | ServiceMonitor for Prometheus scraping of the secured metrics endpoint. The endpoint uses controller-runtime's authn/authz filter, so the scraper must present an authorized identity, not merely the manager's own token. |
| serviceMonitor.enabled | bool | `true` | Ship a ServiceMonitor. |
| serviceMonitor.interval | string | `"30s"` | Scrape interval. |
| serviceMonitor.scraper | object | `{"create":true,"externalSecret":{"key":"token","name":""},"serviceAccountName":""}` | Least-privilege scraper identity with get on the /metrics non-resource URL. |
| serviceMonitor.scraper.create | bool | `true` | Create the scraper ServiceAccount, ClusterRole, binding, and token Secret. |
| serviceMonitor.scraper.externalSecret | object | `{"key":"token","name":""}` | When create=false, an externally-provisioned authorized bearer-token Secret must be named here (with its key). An enabled ServiceMonitor with neither create=true nor an external secret is rejected at render time — an unauthenticated scrape of the authn/authz-filtered endpoint is never allowed. |
| serviceMonitor.scraper.serviceAccountName | string | `""` | ServiceAccount name; defaults to <release>-metrics-reader when empty. |
| trafficCapPercent | int | `20` | Traffic record-removal percentage-per-tick cap. |

----------------------------------------------
Autogenerated from chart metadata using [helm-docs v1.14.2](https://github.com/norwoodj/helm-docs/releases/v1.14.2)
