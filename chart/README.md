# diene-cobalt

![Version: 0.1.0](https://img.shields.io/badge/Version-0.1.0-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square) ![AppVersion: 2.7.0](https://img.shields.io/badge/AppVersion-2.7.0-informational?style=flat-square)

External Secrets Operator plus the Infisical source-of-secrets ClusterSecretStore gateway for AtomiCloud clusters

## Requirements

Kubernetes: `>=1.27.0-0`

| Repository | Name | Version |
|------------|------|---------|
| https://charts.external-secrets.io | eso(external-secrets) | 2.7.0 |

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| eso | object | `{"certController":{"podSecurityContext":{"fsGroup":1000,"runAsGroup":1000,"runAsNonRoot":true,"runAsUser":1000},"resources":{"limits":{"cpu":"250m","memory":"128Mi"},"requests":{"cpu":"50m","memory":"32Mi"}},"securityContext":{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]},"readOnlyRootFilesystem":true,"runAsGroup":1000,"runAsNonRoot":true,"runAsUser":1000},"serviceAccount":{"create":true}},"crds":{"createClusterSecretStore":true,"createSecretStore":true,"unsafeServeV1Beta1":false},"enabled":true,"fullnameOverride":"cobalt-eso","global":{"podAnnotations":{"reloader.stakater.com/auto":"true"}},"image":{"pullPolicy":"IfNotPresent","repository":"ghcr.io/external-secrets/external-secrets","tag":"v2.7.0"},"installCRDs":true,"podSecurityContext":{"fsGroup":1000,"runAsGroup":1000,"runAsNonRoot":true,"runAsUser":1000},"replicaCount":1,"resources":{"limits":{"cpu":"500m","memory":"256Mi"},"requests":{"cpu":"50m","memory":"64Mi"}},"securityContext":{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]},"readOnlyRootFilesystem":true,"runAsGroup":1000,"runAsNonRoot":true,"runAsUser":1000},"serviceAccount":{"create":true},"webhook":{"podSecurityContext":{"fsGroup":1000,"runAsGroup":1000,"runAsNonRoot":true,"runAsUser":1000},"resources":{"limits":{"cpu":"250m","memory":"128Mi"},"requests":{"cpu":"50m","memory":"32Mi"}},"securityContext":{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]},"readOnlyRootFilesystem":true,"runAsGroup":1000,"runAsNonRoot":true,"runAsUser":1000},"serviceAccount":{"create":true}}}` | Vendored External Secrets Operator (upstream external-secrets 2.7.0). Pull-only; CRDs ride helm upgrade via installCRDs and v1beta1 serving stays disabled. |
| eso.crds.unsafeServeV1Beta1 | bool | `false` | v1beta1 serving is deprecated upstream; cobalt authors v1 resources only. |
| eso.global.podAnnotations | object | `{"reloader.stakater.com/auto":"true"}` | Pod annotations inherited by the ESO controller, webhook, and cert-controller. Set this annotation to the string "false" to opt an unsafe deployment out. |
| eso.podSecurityContext | object | `{"fsGroup":1000,"runAsGroup":1000,"runAsNonRoot":true,"runAsUser":1000}` | Workload hardening so the rendered operator satisfies the diene workload VAP. |
| fullnameOverride | string | `"cobalt-sos"` | Primary resource fullname. It must be `<service>-<dashless-token>` (`cobalt-sos`). |
| labelPrefix | string | `"atomi.cloud"` | Prefix used by every service-tree label and annotation helper. |
| serviceTree | object | `{"layer":"1","module":"sos","platform":"cluster","service":"cobalt"}` | Layer-1 service-tree projection. cobalt is cluster-wide infrastructure, so the platform slot is a layer-1 scope marker rather than a service-platform namespace; landscape and cluster are added by independent overlays. |
| store | object | `{"enabled":true,"infisical":{"auth":{"universalAuth":{"clientId":{"key":"clientId","name":"cobalt-sos-bootstrap","namespace":"external-secrets"},"clientSecret":{"key":"clientSecret","name":"cobalt-sos-bootstrap","namespace":"external-secrets"}}},"hostAPI":"https://secrets.atomi.cloud/api","secretsScope":{"environmentSlug":"","projectSlug":"sos","recursive":false,"secretsPath":"/"}}}` | Pull-only SoS Infisical ClusterSecretStore. It reads the cluster landscape's SoS tokens and nothing else; it never writes (no PushSecret) and never inlines credentials. |
| store.infisical.auth | object | `{"universalAuth":{"clientId":{"key":"clientId","name":"cobalt-sos-bootstrap","namespace":"external-secrets"},"clientSecret":{"key":"clientSecret","name":"cobalt-sos-bootstrap","namespace":"external-secrets"}}}` | Universal-auth credential reference. The bootstrap Secret is written into the cluster by the T3 cluster controller; cobalt only consumes it (no literals). |
| store.infisical.hostAPI | string | `"https://secrets.atomi.cloud/api"` | Infisical API base URL (AtomiCloud source of secrets). |
| store.infisical.secretsScope.environmentSlug | string | `""` | The cluster landscape; set by the landscape overlay (env == landscape). |
| store.infisical.secretsScope.projectSlug | string | `"sos"` | The source-of-secrets Infisical project (tokens only). |
| store.infisical.secretsScope.recursive | bool | `false` | Stay non-recursive so the store never reads beyond the landscape path. |
| store.infisical.secretsScope.secretsPath | string | `"/"` | Secret path prefix inside the project; the whole SoS tree is read. |

----------------------------------------------
Autogenerated from chart metadata using [helm-docs v1.14.2](https://github.com/norwoodj/helm-docs/releases/v1.14.2)
