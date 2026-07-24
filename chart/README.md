# diene-sulfur

![Version: 0.1.0](https://img.shields.io/badge/Version-0.1.0-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square) ![AppVersion: v1.20.3](https://img.shields.io/badge/AppVersion-v1.20.3-informational?style=flat-square)

Pure passthrough cert-manager engine wrapper chart for AtomiCloud platform landscapes

## Requirements

Kubernetes: `>=1.22.0-0`

| Repository | Name | Version |
|------------|------|---------|
| https://charts.jetstack.io | certManager(cert-manager) | v1.20.3 |

## What sulfur owns (and does not)

sulfur is a **pure passthrough** wrapper over the upstream `jetstack/cert-manager`
engine (controller + cainjector + webhook). It adds **no Issuer/ClusterIssuer** of
its own: the issuer set is [zinc](https://github.com/AtomiCloud)'s separate chart.
The engine and the issuer set are deliberately independent concerns.

The wrapper carries only minimal upstream overrides:

- `certManager.crds.enabled: true` / `certManager.crds.keep: true` — CRDs install
  with the release and survive uninstall so issued certificates are not garbage
  collected. No separate skipCrds/Server-Side-Apply CRD channel is used.
- `certManager.config.enableGatewayAPI: true` — Gateway/HTTPRoute TLS support for
  kgateway, enabled through the **stable** config field, never the dead
  `ExperimentalGatewayAPISupport` feature gate (a no-op since it defaulted true in
  v1.15).
- resource envelopes and baseline-plus container hardening on every rendered
  workload (controller, webhook, cainjector, startupapicheck) so the shared VAP
  profile passes.
- Reloader opt-in (`reloader.stakater.com/auto`) on each engine Deployment.

## Identity and labels

`global.commonLabels` projects the static service-tree labels onto every upstream
cert-manager resource. The namespace-sourced platform label cannot be a static
value, so the wrapper-owned `sulfur-lpsm` ConfigMap carries the full dynamic LPSM
projection (platform = release namespace, plus the landscape/service/module/layer
slots and reversible physical-instance annotations). `global.serviceTree.platform`
is forbidden as a value — platform always comes from the release namespace.

## Upstream selection and upgrade policy

The vendored dependency is official cert-manager chart `v1.20.3` / app `v1.20.3`,
pinned pure-passthrough from the recorded source archive hash in
`chart/upstream-evidence.yaml`. The official latest is `v1.21.0` (one sequential
minor ahead); it is not adopted because the wrapper advances **one minor at a
time** under the Q-G22 sequential-minor policy in `chart/upgrade-policy.yaml`. The
CRD upgrade path follows the same rule. `pls latest` checks the official
repository and image registry against the recorded evidence.

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| certManager | object | `{"cainjector":{"containerSecurityContext":{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]},"readOnlyRootFilesystem":true,"runAsNonRoot":true},"deploymentAnnotations":{"reloader.stakater.com/auto":"true"},"replicaCount":1,"resources":{"limits":{"cpu":"100m","memory":"128Mi"},"requests":{"cpu":"10m","memory":"32Mi"}}},"config":{"apiVersion":"controller.config.cert-manager.io/v1alpha1","enableGatewayAPI":true,"kind":"ControllerConfiguration"},"containerSecurityContext":{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]},"readOnlyRootFilesystem":true,"runAsNonRoot":true},"crds":{"enabled":true,"keep":true},"deploymentAnnotations":{"reloader.stakater.com/auto":"true"},"fullnameOverride":"cert-manager","replicaCount":1,"resources":{"limits":{"cpu":"100m","memory":"128Mi"},"requests":{"cpu":"10m","memory":"32Mi"}},"startupapicheck":{"containerSecurityContext":{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]},"readOnlyRootFilesystem":true,"runAsNonRoot":true},"resources":{"limits":{"cpu":"100m","memory":"128Mi"},"requests":{"cpu":"10m","memory":"32Mi"}}},"webhook":{"containerSecurityContext":{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]},"readOnlyRootFilesystem":true,"runAsNonRoot":true},"deploymentAnnotations":{"reloader.stakater.com/auto":"true"},"replicaCount":1,"resources":{"limits":{"cpu":"100m","memory":"128Mi"},"requests":{"cpu":"10m","memory":"32Mi"}}}}` | Pure passthrough of the vendored jetstack/cert-manager engine. The wrapper adds NO Issuer/ClusterIssuer of its own — the issuer set is zinc's separate chart; sulfur owns only the cert-manager engine. This map carries only the minimal upstream overrides: CRD installation, the stable Gateway API config field, resource envelopes, container hardening, and Reloader opt-in. |
| certManager.config | object | `{"apiVersion":"controller.config.cert-manager.io/v1alpha1","enableGatewayAPI":true,"kind":"ControllerConfiguration"}` | cert-manager controller runtime configuration (ControllerConfiguration). Gateway API support (Gateway/HTTPRoute TLS for kgateway) is enabled through the stable `enableGatewayAPI` config field. The dead `ExperimentalGatewayAPISupport` feature gate (a no-op since it defaulted true in v1.15) is deliberately NOT set anywhere; the hygiene gate rejects it. |
| certManager.containerSecurityContext | object | `{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]},"readOnlyRootFilesystem":true,"runAsNonRoot":true}` | Baseline-plus container hardening for the controller (upstream omits the container-level runAsNonRoot the VAP profile requires). |
| certManager.crds | object | `{"enabled":true,"keep":true}` | CRD lifecycle stance. CRDs are installed as Helm-managed objects and kept on release uninstall (`keep: true`) so issued Certificates/Issuers survive a chart removal. cert-manager applies CRDs through Helm's ordinary object channel (no separate skipCrds/Server-Side-Apply CRD path is used). |
| certManager.crds.enabled | bool | `true` | Install the cert-manager CRDs with the release. |
| certManager.crds.keep | bool | `true` | Retain CRDs on uninstall to protect existing custom resources. |
| certManager.deploymentAnnotations | object | `{"reloader.stakater.com/auto":"true"}` | Reloader opt-in on the controller Deployment; restarts on config change. |
| certManager.fullnameOverride | string | `"cert-manager"` | Pin the canonical upstream `cert-manager*` object names (pure passthrough). Without this the aliased dependency would fold the alias into every name and emit non-DNS-1123 identifiers. |
| certManager.replicaCount | int | `1` | Single controller replica; cert-manager leader-elects, so one active instance is the generic default. |
| certManager.resources | object | `{"limits":{"cpu":"100m","memory":"128Mi"},"requests":{"cpu":"10m","memory":"32Mi"}}` | CPU and memory envelopes for the controller container (VAP requires both requests and limits on every workload container). |
| global | object | `{"commonLabels":{"atomi.cloud/layer":"1","atomi.cloud/module":"certs","atomi.cloud/service":"sulfur"},"instance":{"physicalId":"example-repository:run-001"},"labelPrefix":"atomi.cloud","serviceTree":{"layer":"1","module":"certs","service":"sulfur"}}` | Values shared with the vendored cert-manager dependency through Helm's supported parent-to-subchart global-values contract. |
| global.commonLabels | object | `{"atomi.cloud/layer":"1","atomi.cloud/module":"certs","atomi.cloud/service":"sulfur"}` | Static service-tree labels projected onto every upstream cert-manager resource through cert-manager's supported `global.commonLabels` passthrough. The namespace-sourced platform label cannot be expressed as a static value, so the wrapper-owned LPSM ConfigMap carries the full dynamic LPSM projection. Overlays append the landscape label. Keys must stay consistent with `global.serviceTree`; the unit `labels` gate enforces the correspondence. |
| global.instance | object | `{"physicalId":"example-repository:run-001"}` | Optional physical-instance metadata. The instance remains outside LPSM. |
| global.instance.physicalId | string | `"example-repository:run-001"` | Repository-qualified physical instance id. |
| global.labelPrefix | string | `"atomi.cloud"` | Single prefix used by every wrapper service-tree label and annotation helper. |
| global.serviceTree | object | `{"layer":"1","module":"certs","service":"sulfur"}` | Stable service-tree projection. Platform is always the release namespace; landscape and cluster are added by independent overlays. |
| global.serviceTree.layer | string | `"1"` | Architecture layer. |
| global.serviceTree.module | string | `"certs"` | Module name. |
| global.serviceTree.service | string | `"sulfur"` | Service name. |
