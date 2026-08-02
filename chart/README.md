# diene-helm-wrapper

![Version: 0.1.0](https://img.shields.io/badge/Version-0.1.0-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square) ![AppVersion: 6.9.2](https://img.shields.io/badge/AppVersion-6.9.2-informational?style=flat-square)

Minimal production-grade Helm wrapper template for AtomiCloud platform charts

## Requirements

Kubernetes: `>=1.27.0-0`

| Repository | Name | Version |
|------------|------|---------|
| oci://ghcr.io/stefanprodan/charts | upstream(podinfo) | 6.9.2 |

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| contracts | object | `{"health":{"expectedStatus":"2xx","path":"/healthz"},"lpsm":{"instance":"run001","instanceZone":"local.example.invalid","landscape":"example","module":"api","ordinaryZone":"cluster.atomi.cloud","parseHostname":"","service":"wrapper"},"webhook":{"pathPrefix":"/internal/webhooks","provider":"example"}}` | Current health and webhook delivery conventions. |
| fullnameOverride | string | `"wrapper-api"` | Primary workload fullname. It must be `<service>-<dashless-token>`. |
| gateway | object | `{"aws":{"eipAllocationIds":[],"subnetIds":[]},"enabled":true,"oci":{"reservedPublicIp":""},"port":80,"provider":"digitalocean"}` | Provider-managed LoadBalancer service for the gateway. |
| instance | object | `{"physicalId":"example-repository:run-001"}` | Optional physical-instance metadata. The instance remains outside LPSM. |
| labelPrefix | string | `"atomi.cloud"` | Prefix used by every service-tree label and annotation helper. |
| migration | object | `{"command":["sh","-c","echo migration-ready"],"enabled":true,"image":{"pullPolicy":"IfNotPresent","repository":"busybox","tag":"1.37.0-glibc"},"reloader":{"enabled":true},"resources":{"limits":{"cpu":"25m","memory":"32Mi"},"requests":{"cpu":"5m","memory":"8Mi"}}}` | Separate pre-sync migration hook. It never owns or recreates the Deployment. |
| primordial | object | `{"apiVersions":{"edge":"edge.atomi.cloud/v1alpha1","fleet":"fleet.atomi.cloud/v1alpha1","identity":"identity.atomi.cloud/v1alpha1"},"cloudflareDeploy":{"enabled":true,"pin":true,"scriptName":"wrapper-web","tag":"0.1.0"},"enabled":true,"logtoApp":{"enabled":true,"extraRedirectUris":[],"paths":["/auth/callback"],"resourceRefs":["wrapper-api"]},"placement":{"preferredHost":"example-host"},"platformDependency":{"modules":{"cache":{"hot":{"credentialMode":"standard","delivery":"replicated","engine":{"dragonfly":{}},"ram":"128Mi","rotation":"on","type":"dragonfly"}},"database":{"maindb":{"backup":{"crossVendor":true},"cpu":1,"credentialMode":"standard","delivery":"external","engine":{"neon":{"tier":"example"}},"providerAccountRef":"example-neon","ram":"1Gi","rotation":"on","storage":"10Gi","type":"neon","version":"16"}},"kv":{"sessions":{"credentialMode":"standard","delivery":"external","engine":{"upstash":{}},"providerAccountRef":"example-upstash","ram":"128Mi","rotation":"on","type":"upstash"}},"store":{"assets":{"credentialMode":"standard","delivery":"external","engine":{"tigris":{}},"providerAccountRef":"example-tigris","rotation":"on","type":"tigris"}}}},"problem":{"enabled":true,"entries":[{"endpoints":[{"method":"GET","path":"/"}],"id":"example","recoverable":false,"schema":{},"status":500,"title":"Example problem","type":"https://errors.example.invalid/example"}],"version":"0.1.0"},"targetLandscape":"example","virtualLandscapeService":{"enabled":true,"serve":true},"vlandscape":"example-vlandscape"}` | Reusable primordial-chart CR helper inputs against the frozen T3 shapes. |
| secret | object | `{"enabled":true,"refreshInterval":"1h","serviceFolder":"/wrapper","sharedFolder":"/shared","store":{"kind":"SecretStore","name":"sample-store"}}` | One service-scoped ExternalSecret with folder-prefix rewrites. |
| serviceTree | object | `{"layer":"2","module":"api","platform":"sample","service":"wrapper"}` | Stable four-slot service-tree projection. Landscape and cluster are added by independent overlays. |
| upstream | object | `{"enabled":false,"fullnameOverride":"wrapper-upstream","image":{"repository":"ghcr.io/stefanprodan/podinfo","tag":"6.9.2"},"podAnnotations":{"reloader.stakater.com/auto":"true"},"podSecurityContext":{"runAsGroup":10000,"runAsNonRoot":true,"runAsUser":10000},"resources":{"limits":{"cpu":"100m","memory":"128Mi"},"requests":{"cpu":"10m","memory":"32Mi"}},"securityContext":{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]},"readOnlyRootFilesystem":true,"runAsGroup":10000,"runAsNonRoot":true,"runAsUser":10000}}` | Pinned optional upstream chart. Every instantiated dependency must receive a conforming override. |
| webhookRoute | object | `{"enabled":true,"parentGateway":"sample-gateway","parentNamespace":"gateway-system"}` | Optional Gateway API route scaffold for a webhook receiver. |
| workload | object | `{"image":{"pullPolicy":"IfNotPresent","repository":"ghcr.io/stefanprodan/podinfo","tag":"6.9.2"},"podSecurityContext":{"fsGroup":10000,"runAsGroup":10000,"runAsNonRoot":true,"runAsUser":10000},"port":9898,"reloader":{"enabled":true},"replicas":1,"resources":{"limits":{"cpu":"100m","memory":"128Mi"},"requests":{"cpu":"10m","memory":"32Mi"}},"securityContext":{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]},"readOnlyRootFilesystem":true,"runAsGroup":10000,"runAsNonRoot":true,"runAsUser":10000}}` | Wrapper-owned sample workload. |

----------------------------------------------
Autogenerated from chart metadata using [helm-docs v1.14.2](https://github.com/norwoodj/helm-docs/releases/v1.14.2)
