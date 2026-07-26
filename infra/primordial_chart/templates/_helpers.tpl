{{/* ### bun-consumer-primordial-helpers */}}
{{/* #### source: bun-consumer */}}

{{/* Stable chart identity. */}}
{{- define "bunconsumerPrimordial.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/* The one and only service-tree label/annotation prefix (R16/B26). */}}
{{- define "bunconsumerPrimordial.labelPrefix" -}}
{{- required "labelPrefix is required" .Values.labelPrefix | trimSuffix "/" -}}
{{- end -}}

{{/* Validate the LPSM projection before anything renders. */}}
{{- define "bunconsumerPrimordial.validateServiceTree" -}}
{{- $serviceTree := required "serviceTree is required" .Values.serviceTree -}}
{{- $platform := required "serviceTree.platform is required" $serviceTree.platform -}}
{{- $service := required "serviceTree.service is required" $serviceTree.service -}}
{{- $_ := required "serviceTree.module is required" $serviceTree.module -}}
{{- $_ = required "serviceTree.layer is required" $serviceTree.layer -}}
{{- if not (regexMatch "^[a-z0-9]+$" $service) -}}
{{- fail (printf "serviceTree.service %q must be a dash-less lowercase token (fullname convention <service>-<token>, B30.4)" $service) -}}
{{- end -}}
{{- if not (regexMatch "^[a-z0-9]([-a-z0-9]*[a-z0-9])?$" $platform) -}}
{{- fail (printf "serviceTree.platform %q must be a DNS-1123 label" $platform) -}}
{{- end -}}
{{- end -}}

{{/* Build an exactly-one-dash resource name from service + fused token (B30.4). */}}
{{- define "bunconsumerPrimordial.resourceName" -}}
{{- $root := .root -}}
{{- $service := required "serviceTree.service is required" $root.Values.serviceTree.service | lower -}}
{{- $token := required "resource token is required" .token | lower -}}
{{- $token = regexReplaceAll "[^a-z0-9]+" $token "" -}}
{{- if not (regexMatch "^[a-z0-9]+$" $token) -}}
{{- fail (printf "token %q must normalize to a dash-less lowercase token" .token) -}}
{{- end -}}
{{- printf "%s-%s" $service $token -}}
{{- end -}}

{{/* `<platform>-<service>` — the prefix every deterministic Grafana uid is built
     from (observability standard, Contract 2). */}}
{{- define "bunconsumerPrimordial.grafanaPrefix" -}}
{{- printf "%s-%s" .Values.serviceTree.platform .Values.serviceTree.service -}}
{{- end -}}

{{/* The service folder uid. The `-folder` suffix keeps it out of the shared
     dashboard/alert-group uid pool. */}}
{{- define "bunconsumerPrimordial.grafanaFolderUid" -}}
{{- printf "%s-folder" (include "bunconsumerPrimordial.grafanaPrefix" .) -}}
{{- end -}}

{{/* Service-tree labels only; every key is prefixed by labelPrefix. */}}
{{- define "bunconsumerPrimordial.serviceTreeLabels" -}}
{{- $prefix := include "bunconsumerPrimordial.labelPrefix" . -}}
{{- range $key, $value := .Values.serviceTree }}
{{ printf "%s/%s" $prefix $key }}: {{ $value | quote }}
{{- end }}
{{- end -}}

{{/* Labels for every owned resource. */}}
{{- define "bunconsumerPrimordial.labels" -}}
helm.sh/chart: {{ include "bunconsumerPrimordial.chart" . }}
app.kubernetes.io/name: {{ .Values.serviceTree.service | quote }}
app.kubernetes.io/instance: {{ .Release.Name | quote }}
app.kubernetes.io/component: primordial
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: {{ .Values.serviceTree.platform | quote }}
{{- include "bunconsumerPrimordial.serviceTreeLabels" . }}
{{- end -}}

{{/* Service-tree annotations for every owned resource. */}}
{{- define "bunconsumerPrimordial.annotations" -}}
{{ include "bunconsumerPrimordial.serviceTreeLabels" . | trim }}
{{- end -}}

{{/* The LPSM labels merged into every alert rule. The observability standard is
     explicit that authors never hand-write these — the renderer injects them
     (Contract 1). Only the plain service-tree slots are projected: alert routing
     matches on unprefixed `platform`/`service`/`module`/`landscape`/`severity`. */}}
{{- define "bunconsumerPrimordial.alertLabels" -}}
{{- range $key, $value := .Values.serviceTree }}
{{ $key }}: {{ $value | quote }}
{{- end }}
{{- end -}}
