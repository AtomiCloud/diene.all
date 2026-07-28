# platinum

![Version: 0.1.0](https://img.shields.io/badge/Version-0.1.0-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square) ![AppVersion: v2.2.9](https://img.shields.io/badge/AppVersion-v2.2.9-informational?style=flat-square)

AtomiCloud platform Gateway API ingress chart wrapping kgateway (element platinum)

## Requirements

Kubernetes: `>=1.27.0-0`

| Repository | Name | Version |
|------------|------|---------|
| oci://cr.kgateway.dev/kgateway-dev/charts | upstream(kgateway) | v2.2.9 |
| oci://cr.kgateway.dev/kgateway-dev/charts | kgateway-crds | v2.2.9 |

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| devHost | object | `{"enabled":false}` | ENTEI dev-host shared-Gateway mode. When enabled, platinum renders the shared GatewayClass, Gateway, and LoadBalancer only; per-host Certificate, ListenerSet, and HTTPRoute are owned by the exposure materializer, not this chart. |
| fullnameOverride | string | `"platinum-api"` | Primary workload fullname (`<service>-<token>`). The wrapper convention names the chart's primary served endpoint. |
| gateway | object | `{"aws":{"eipAllocationIds":[],"subnetIds":[]},"classname":"platinum","controllerName":"kgateway.dev/kgateway","enabled":true,"health":{"expectedStatus":"2xx","path":"/healthz"},"oci":{"reservedPublicIp":""},"port":80,"provider":"digitalocean","proxy":{"httpTargetPort":80,"httpsTargetPort":443,"selector":{"app.kubernetes.io/instance":"platinum-gateway","app.kubernetes.io/name":"platinum-gateway","gateway.networking.k8s.io/gateway-name":"platinum-gateway"}},"tlsPort":443}` | Gateway API edge: shared GatewayClass, shared Gateway, the LoadBalancer exposure, and the health route. |
| gateway.classname | string | `"platinum"` | GatewayClass name platinum owns. Registered-fleet and local LAPRAS-class gateways reference it. |
| gateway.controllerName | string | `"kgateway.dev/kgateway"` | Controller binding pinned to kgateway v2.2.9's real controller name. |
| gateway.health.path | string | `"/healthz"` | Fixed health path the traffic controller polls once per cluster per tick. |
| gateway.proxy.httpTargetPort | int | `80` | Generated v2.2.9 proxy container port for the HTTP listener. |
| gateway.proxy.httpsTargetPort | int | `443` | Generated v2.2.9 proxy container port for the HTTPS listeners. |
| gateway.proxy.selector | object | `{"app.kubernetes.io/instance":"platinum-gateway","app.kubernetes.io/name":"platinum-gateway","gateway.networking.k8s.io/gateway-name":"platinum-gateway"}` | Exact stable labels on the v2.2.9 proxy generated for Gateway platinum-gateway. |
| healthBackend | object | `{"enabled":true,"image":{"pullPolicy":"IfNotPresent","repository":"ghcr.io/stefanprodan/podinfo","tag":"6.9.2"},"podSecurityContext":{"fsGroup":10000,"runAsGroup":10000,"runAsNonRoot":true,"runAsUser":10000},"port":9898,"reloader":{"enabled":true},"replicas":1,"resources":{"limits":{"cpu":"100m","memory":"128Mi"},"requests":{"cpu":"10m","memory":"32Mi"}},"securityContext":{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]},"readOnlyRootFilesystem":true,"runAsGroup":10000,"runAsNonRoot":true,"runAsUser":10000}}` | Platinum-owned /healthz responder. It is the gateway health-route backend and the chart's primary workload. |
| instance | object | `{"physicalId":"example-repository:run-001"}` | Optional physical-instance metadata. The instance remains outside LPSM. |
| kgatewayCrds | object | `{"enabled":false}` | Standard-channel and kgateway CRD subchart. Enabled in the k3d integration tier; off for unit-tier static checks. |
| labelPrefix | string | `"atomi.cloud"` | Prefix used by every service-tree label and annotation helper. |
| registeredCertificates | object | `{"backup":{"dnsNames":["*.atomi.cloud.failover","atomi.cloud.failover"],"domain":"*.atomi.cloud.failover"},"enabled":true,"issuerRef":{"kind":"ClusterIssuer","name":"zinc-wildcard-letsencrypt"},"primary":{"dnsNames":["*.atomi.cloud","atomi.cloud"],"domain":"*.atomi.cloud"}}` | Registered-fleet wildcard Certificates. Zinc owns the DNS-01 ClusterIssuer definition (charts/zinc); this chart only issues against it. |
| registeredCertificates.backup.domain | string | `"*.atomi.cloud.failover"` | Second R53 base-domain wildcard for cluster-endpoint failover TLS (S8 backup domain). |
| registeredCertificates.issuerRef.name | string | `"zinc-wildcard-letsencrypt"` | ClusterIssuer name owned by charts/zinc and instantiated once per cluster. |
| registeredCertificates.primary.domain | string | `"*.atomi.cloud"` | Primary registered-fleet base-domain wildcard (atomi.cloud). |
| serviceTree | object | `{"layer":"1","module":"gateway","platform":"sulfoxide","service":"platinum"}` | Stable four-slot service-tree projection. Landscape and cluster are added by independent overlays. |
| upstream | object | `{"controller":{"image":{"repository":"kgateway","tag":"v2.2.9"},"service":{"type":"ClusterIP"}},"enabled":false,"fullnameOverride":"platinum-upstream"}` | Pinned kgateway control-plane subchart. Enabled in the k3d integration tier; off for unit-tier static checks. |

----------------------------------------------
Autogenerated from chart metadata using [helm-docs v1.14.2](https://github.com/norwoodj/helm-docs/releases/v1.14.2)
