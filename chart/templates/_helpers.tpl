{{/* Stable chart identity. */}}
{{- define "vanadium.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/* The one and only service-tree label/annotation prefix. */}}
{{- define "vanadium.labelPrefix" -}}
{{- required "labelPrefix is required" .Values.labelPrefix | trimSuffix "/" -}}
{{- end -}}

{{/* Common selector labels. */}}
{{- define "vanadium.selectorLabels" -}}
app.kubernetes.io/name: vanadium
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{/* Chart + service-tree labels. Every key uses the single configurable prefix. */}}
{{- define "vanadium.labels" -}}
{{- $prefix := include "vanadium.labelPrefix" . -}}
helm.sh/chart: {{ include "vanadium.chart" . }}
{{ include "vanadium.selectorLabels" . }}
{{- range $key, $value := .Values.serviceTree }}
{{ printf "%s/%s" $prefix $key }}: {{ $value | quote }}
{{- end }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{/* Service-tree annotations (identity is never a secret). */}}
{{- define "vanadium.annotations" -}}
{{- $prefix := include "vanadium.labelPrefix" . -}}
{{- range $key, $value := .Values.serviceTree }}
{{ printf "%s/%s" $prefix $key }}: {{ $value | quote }}
{{- end }}
{{- end -}}

{{/* Build an exactly-one-dash policy name: vanadium-<dashless-token>. */}}
{{- define "vanadium.policyName" -}}
{{- $root := .root -}}
{{- $service := required "serviceTree.service is required" $root.Values.serviceTree.service | lower -}}
{{- $token := required "policy name (token) is required" .name | lower -}}
{{- $token = regexReplaceAll "[^a-z0-9]+" $token "" -}}
{{- if not (regexMatch "^[a-z0-9]+$" $service) -}}
{{- fail (printf "service %q must be dash-less lowercase alphanumeric" $service) -}}
{{- end -}}
{{- if not (regexMatch "^[a-z0-9]+$" $token) -}}
{{- fail (printf "policy token %q must normalize to a dash-less lowercase token" .name) -}}
{{- end -}}
{{- printf "%s-%s" $service $token -}}
{{- end -}}

{{/* Namespace-label exemption selector. A namespace labeled
     `<prefix>/<exemption.labelKey>: "true"` is exempt from every binding. */}}
{{- define "vanadium.exemptionSelector" -}}
{{- $prefix := include "vanadium.labelPrefix" . -}}
{{- $key := printf "%s/%s" $prefix (required "exemption.labelKey is required" .Values.exemption.labelKey) -}}
matchExpressions:
  - key: {{ $key | quote }}
    operator: NotIn
    values:
      - 'true'
{{- end -}}

{{/* resourceRules fragments shared across policies. */}}
{{- define "vanadium.rules.workload" -}}
- apiGroups: [apps, batch]
  apiVersions: [v1]
  operations: [CREATE, UPDATE]
  resources: [deployments, statefulsets, daemonsets, jobs]
{{- end -}}

{{- define "vanadium.rules.service" -}}
- apiGroups: ['']
  apiVersions: [v1]
  operations: [CREATE, UPDATE]
  resources: [services]
{{- end -}}

{{- define "vanadium.rules.workloadAndService" -}}
{{ include "vanadium.rules.workload" . }}
{{ include "vanadium.rules.service" . }}
{{- end -}}

{{/* ---- per-policy resourceRules selectors ---- */}}
{{- define "vanadium.match.requireLabels" -}}{{ include "vanadium.rules.workloadAndService" . }}{{- end -}}
{{- define "vanadium.match.requireAnnotations" -}}{{ include "vanadium.rules.workloadAndService" . }}{{- end -}}
{{- define "vanadium.match.landscapeMatch" -}}{{ include "vanadium.rules.workloadAndService" . }}{{- end -}}
{{- define "vanadium.match.layerRange" -}}{{ include "vanadium.rules.workloadAndService" . }}{{- end -}}
{{- define "vanadium.match.platformAccepted" -}}{{ include "vanadium.rules.workloadAndService" . }}{{- end -}}
{{- define "vanadium.match.disallowLatest" -}}{{ include "vanadium.rules.workload" . }}{{- end -}}
{{- define "vanadium.match.requireResources" -}}{{ include "vanadium.rules.workload" . }}{{- end -}}
{{- define "vanadium.match.disallowNodePort" -}}{{ include "vanadium.rules.service" . }}{{- end -}}
{{- define "vanadium.match.requireNonRoot" -}}{{ include "vanadium.rules.workload" . }}{{- end -}}
{{- define "vanadium.match.disallowPrivEscalation" -}}{{ include "vanadium.rules.workload" . }}{{- end -}}
{{- define "vanadium.match.restrictVolumeTypes" -}}{{ include "vanadium.rules.workload" . }}{{- end -}}

{{/* ---- per-policy human messages ---- */}}
{{- define "vanadium.message.requireLabels" -}}Workloads and services must carry the full LPSM label set (landscape, platform, service, module, layer).{{- end -}}
{{- define "vanadium.message.requireAnnotations" -}}Workloads and services must carry the full LPSM annotation set (landscape, platform, service, module, layer).{{- end -}}
{{- define "vanadium.message.landscapeMatch" -}}LPSM landscape label and annotation must equal this cluster's landscape.{{- end -}}
{{- define "vanadium.message.layerRange" -}}LPSM layer must be one of the accepted layers.{{- end -}}
{{- define "vanadium.message.platformAccepted" -}}LPSM platform must be in the accepted platform list.{{- end -}}
{{- define "vanadium.message.disallowLatest" -}}Workload images must use an explicit non-latest tag.{{- end -}}
{{- define "vanadium.message.requireResources" -}}Every container must declare CPU and memory requests and limits.{{- end -}}
{{- define "vanadium.message.disallowNodePort" -}}NodePort services are forbidden; use ClusterIP or LoadBalancer.{{- end -}}
{{- define "vanadium.message.requireNonRoot" -}}Workloads must run non-root at the pod and container level.{{- end -}}
{{- define "vanadium.message.disallowPrivEscalation" -}}Containers must not allow privilege escalation.{{- end -}}
{{- define "vanadium.message.restrictVolumeTypes" -}}hostPath volumes are forbidden outside the alloy /var/log container-logs carve-out.{{- end -}}

{{/* ---- per-policy CEL expressions (object-only; rendered literals come from values) ---- */}}
{{/* requireLabels: the five LPSM keys must be present as labels. */}}
{{- define "vanadium.cel.requireLabels" -}}
{{- $p := include "vanadium.labelPrefix" . -}}
has(object.metadata) && has(object.metadata.labels) &&
"{{ $p }}/landscape" in object.metadata.labels &&
"{{ $p }}/platform" in object.metadata.labels &&
"{{ $p }}/service" in object.metadata.labels &&
"{{ $p }}/module" in object.metadata.labels &&
"{{ $p }}/layer" in object.metadata.labels
{{- end -}}

{{/* requireAnnotations: the five LPSM keys must be present as annotations. */}}
{{- define "vanadium.cel.requireAnnotations" -}}
{{- $p := include "vanadium.labelPrefix" . -}}
has(object.metadata) && has(object.metadata.annotations) &&
"{{ $p }}/landscape" in object.metadata.annotations &&
"{{ $p }}/platform" in object.metadata.annotations &&
"{{ $p }}/service" in object.metadata.annotations &&
"{{ $p }}/module" in object.metadata.annotations &&
"{{ $p }}/layer" in object.metadata.annotations
{{- end -}}

{{/* landscapeMatch: label and annotation landscape equal the cluster landscape. */}}
{{- define "vanadium.cel.landscapeMatch" -}}
{{- $p := include "vanadium.labelPrefix" . -}}
{{- $landscape := required "params.landscape is required" .Values.params.landscape -}}
has(object.metadata) && has(object.metadata.labels) && has(object.metadata.annotations) &&
"{{ $p }}/landscape" in object.metadata.labels &&
"{{ $p }}/landscape" in object.metadata.annotations &&
object.metadata.labels["{{ $p }}/landscape"] == "{{ $landscape }}" &&
object.metadata.annotations["{{ $p }}/landscape"] == "{{ $landscape }}"
{{- end -}}

{{/* layerRange: layer label is one of the accepted layers. */}}
{{- define "vanadium.cel.layerRange" -}}
{{- $p := include "vanadium.labelPrefix" . -}}
{{- $layers := .Values.params.acceptedLayers | toJson -}}
has(object.metadata) && has(object.metadata.labels) &&
"{{ $p }}/layer" in object.metadata.labels &&
{{ $layers }}.exists(x, x == object.metadata.labels["{{ $p }}/layer"])
{{- end -}}

{{/* platformAccepted: platform label is in the accepted list. */}}
{{- define "vanadium.cel.platformAccepted" -}}
{{- $p := include "vanadium.labelPrefix" . -}}
{{- $platforms := .Values.params.acceptedPlatforms | toJson -}}
has(object.metadata) && has(object.metadata.labels) &&
"{{ $p }}/platform" in object.metadata.labels &&
{{ $platforms }}.exists(x, x == object.metadata.labels["{{ $p }}/platform"])
{{- end -}}

{{/* disallowLatest: every container image ends with a non-latest tag or immutable digest. */}}
{{- define "vanadium.cel.disallowLatest" -}}
object.spec.template.spec.containers.all(c,
  (c.image.matches('^(.*/)?[^/@:]+:[^/@:]+$') ||
   c.image.matches('^.+@[^/@:]+:[A-Fa-f0-9]+$')) && !c.image.endsWith(':latest')) &&
(!has(object.spec.template.spec.initContainers) || object.spec.template.spec.initContainers.all(c,
  (c.image.matches('^(.*/)?[^/@:]+:[^/@:]+$') ||
   c.image.matches('^.+@[^/@:]+:[A-Fa-f0-9]+$')) && !c.image.endsWith(':latest')))
{{- end -}}

{{/* requireResources: every container declares cpu+memory requests and limits. */}}
{{- define "vanadium.cel.requireResources" -}}
object.spec.template.spec.containers.all(c,
  has(c.resources) && has(c.resources.requests) && has(c.resources.limits) &&
  has(c.resources.requests.cpu) && has(c.resources.requests.memory) &&
  has(c.resources.limits.cpu) && has(c.resources.limits.memory)) &&
(!has(object.spec.template.spec.initContainers) || object.spec.template.spec.initContainers.all(c,
  has(c.resources) && has(c.resources.requests) && has(c.resources.limits) &&
  has(c.resources.requests.cpu) && has(c.resources.requests.memory) &&
  has(c.resources.limits.cpu) && has(c.resources.limits.memory)))
{{- end -}}

{{/* disallowNodePort: services must not be NodePort. */}}
{{- define "vanadium.cel.disallowNodePort" -}}
!has(object.spec.type) || object.spec.type != 'NodePort'
{{- end -}}

{{/* requireNonRoot: pod and every container run non-root. */}}
{{- define "vanadium.cel.requireNonRoot" -}}
has(object.spec.template.spec.securityContext) &&
object.spec.template.spec.securityContext.runAsNonRoot == true &&
object.spec.template.spec.containers.all(c,
  has(c.securityContext) && c.securityContext.runAsNonRoot == true) &&
(!has(object.spec.template.spec.initContainers) || object.spec.template.spec.initContainers.all(c,
  has(c.securityContext) && c.securityContext.runAsNonRoot == true))
{{- end -}}

{{/* disallowPrivEscalation: no container may allow privilege escalation. */}}
{{- define "vanadium.cel.disallowPrivEscalation" -}}
object.spec.template.spec.containers.all(c,
  has(c.securityContext) && c.securityContext.allowPrivilegeEscalation == false) &&
(!has(object.spec.template.spec.initContainers) || object.spec.template.spec.initContainers.all(c,
  has(c.securityContext) && c.securityContext.allowPrivilegeEscalation == false))
{{- end -}}

{{/* restrictVolumeTypes: PSS restricted source whitelist with a narrow alloy hostPath carve-out. */}}
{{- define "vanadium.cel.restrictVolumeTypes" -}}
!has(object.spec.template.spec.volumes) ||
object.spec.template.spec.volumes.all(v,
  has(v.configMap) || has(v.csi) || has(v.downwardAPI) || has(v.emptyDir) ||
  has(v.ephemeral) || has(v.persistentVolumeClaim) || has(v.projected) ||
  has(v.secret) ||
  (has(v.hostPath) && has(object.spec.template.spec.serviceAccountName) &&
   object.spec.template.spec.serviceAccountName == 'alloy-logs' && has(v.hostPath.path) &&
   (v.hostPath.path == '/var/log' || v.hostPath.path.startsWith('/var/log/'))))
{{- end -}}
