# diene-chlorine

![Version: 0.1.0](https://img.shields.io/badge/Version-0.1.0-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square) ![AppVersion: 1.4.19](https://img.shields.io/badge/AppVersion-1.4.19-informational?style=flat-square)

Minimal Reloader wrapper chart — the last hop of the secret-rotation chain

## Requirements

Kubernetes: `>=1.27.0-0`

| Repository | Name | Version |
|------------|------|---------|
| oci://ghcr.io/stakater/charts | reloader | 2.2.14 |

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| global.instance | object | `{"physicalId":"diene-chlorine:run-001"}` | Optional physical-instance metadata. The instance remains outside LPSM. |
| global.instance.physicalId | string | `"diene-chlorine:run-001"` | Repository-qualified physical instance id. |
| global.labelPrefix | string | `"atomi.cloud"` | Prefix used by every service-tree label and annotation helper. |
| global.serviceTree | object | `{"layer":"1","module":"reloader","service":"chlorine"}` | Stable four-slot service-tree projection. The platform slot is sourced from the release namespace (never a values entry); landscape and cluster arrive from independent overlays. |
| global.serviceTree.layer | string | `"1"` | Architecture layer. |
| global.serviceTree.module | string | `"reloader"` | Module name. |
| global.serviceTree.service | string | `"chlorine"` | Service name. |
| reloader | object | `{"enabled":true,"fullnameOverride":"chlorine-reloader","reloader":{"autoReloadAll":false,"deployment":{"containerSecurityContext":{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]},"runAsNonRoot":true},"labels":{"{{ include \"diene-chlorine.labelPrefix\" . }}/cluster":"{{ .Values.global.serviceTree.cluster | default \"\" }}","{{ include \"diene-chlorine.labelPrefix\" . }}/landscape":"{{ .Values.global.serviceTree.landscape | default \"\" }}","{{ include \"diene-chlorine.labelPrefix\" . }}/layer":"{{ .Values.global.serviceTree.layer }}","{{ include \"diene-chlorine.labelPrefix\" . }}/module":"{{ .Values.global.serviceTree.module }}","{{ include \"diene-chlorine.labelPrefix\" . }}/platform":"{{ include \"diene-chlorine.validateServiceTree\" . }}{{ .Release.Namespace }}","{{ include \"diene-chlorine.labelPrefix\" . }}/service":"{{ .Values.global.serviceTree.service }}"},"pod":{"annotations":{"{{ include \"diene-chlorine.labelPrefix\" . }}/cluster":"{{ .Values.global.serviceTree.cluster | default \"\" }}","{{ include \"diene-chlorine.labelPrefix\" . }}/instance-label":"{{ include \"diene-chlorine.instanceLabel\" .Values.global.instance.physicalId }}","{{ include \"diene-chlorine.labelPrefix\" . }}/instance-original":"{{ .Values.global.instance.physicalId }}","{{ include \"diene-chlorine.labelPrefix\" . }}/landscape":"{{ .Values.global.serviceTree.landscape | default \"\" }}","{{ include \"diene-chlorine.labelPrefix\" . }}/layer":"{{ .Values.global.serviceTree.layer }}","{{ include \"diene-chlorine.labelPrefix\" . }}/module":"{{ .Values.global.serviceTree.module }}","{{ include \"diene-chlorine.labelPrefix\" . }}/platform":"{{ .Release.Namespace }}","{{ include \"diene-chlorine.labelPrefix\" . }}/service":"{{ .Values.global.serviceTree.service }}"}},"resources":{"limits":{"cpu":"100m","memory":"128Mi"},"requests":{"cpu":"10m","memory":"64Mi"}}},"readOnlyRootFileSystem":true,"reloadStrategy":"annotations"}}` | Vendored Stakater Reloader dependency. Chlorine is a near-pure passthrough: the subchart owns the workload; this block only pins the fleet conventions. |
| reloader.fullnameOverride | string | `"chlorine-reloader"` | Exactly-one-dash fullname on the vendored dependency (`<service>-<token>`). |
| reloader.reloader.autoReloadAll | bool | `false` | PRESERVE annotation opt-in. Never auto-reload-all; workloads opt in via the stakater annotation. |
| reloader.reloader.deployment.containerSecurityContext | object | `{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]},"runAsNonRoot":true}` | Baseline-plus container hardening (VAP conformance). |
| reloader.reloader.deployment.labels | object | `{"{{ include \"diene-chlorine.labelPrefix\" . }}/cluster":"{{ .Values.global.serviceTree.cluster | default \"\" }}","{{ include \"diene-chlorine.labelPrefix\" . }}/landscape":"{{ .Values.global.serviceTree.landscape | default \"\" }}","{{ include \"diene-chlorine.labelPrefix\" . }}/layer":"{{ .Values.global.serviceTree.layer }}","{{ include \"diene-chlorine.labelPrefix\" . }}/module":"{{ .Values.global.serviceTree.module }}","{{ include \"diene-chlorine.labelPrefix\" . }}/platform":"{{ include \"diene-chlorine.validateServiceTree\" . }}{{ .Release.Namespace }}","{{ include \"diene-chlorine.labelPrefix\" . }}/service":"{{ .Values.global.serviceTree.service }}"}` | Service-tree labels rendered through the subchart's tpl pipeline. |
| reloader.reloader.deployment.pod.annotations | object | `{"{{ include \"diene-chlorine.labelPrefix\" . }}/cluster":"{{ .Values.global.serviceTree.cluster | default \"\" }}","{{ include \"diene-chlorine.labelPrefix\" . }}/instance-label":"{{ include \"diene-chlorine.instanceLabel\" .Values.global.instance.physicalId }}","{{ include \"diene-chlorine.labelPrefix\" . }}/instance-original":"{{ .Values.global.instance.physicalId }}","{{ include \"diene-chlorine.labelPrefix\" . }}/landscape":"{{ .Values.global.serviceTree.landscape | default \"\" }}","{{ include \"diene-chlorine.labelPrefix\" . }}/layer":"{{ .Values.global.serviceTree.layer }}","{{ include \"diene-chlorine.labelPrefix\" . }}/module":"{{ .Values.global.serviceTree.module }}","{{ include \"diene-chlorine.labelPrefix\" . }}/platform":"{{ .Release.Namespace }}","{{ include \"diene-chlorine.labelPrefix\" . }}/service":"{{ .Values.global.serviceTree.service }}"}` | Service-tree and reversible instance metadata annotations. |
| reloader.reloader.deployment.resources | object | `{"limits":{"cpu":"100m","memory":"128Mi"},"requests":{"cpu":"10m","memory":"64Mi"}}` | Requests and limits (VAP conformance; Reloader is a light controller). |
| reloader.reloader.readOnlyRootFileSystem | bool | `true` | Read-only root filesystem with a chart-managed writable /tmp volume (VAP baseline-plus). |
| reloader.reloader.reloadStrategy | string | `"annotations"` | Only annotated workloads are reloaded (the fleet opt-in posture). |

----------------------------------------------
Autogenerated from chart metadata using [helm-docs v1.14.2](https://github.com/norwoodj/helm-docs/releases/v1.14.2)
