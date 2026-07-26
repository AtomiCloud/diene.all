{{/* ### go-consumer-primordial-helpers */}}
{{/* #### source: go-consumer */}}

{{/* Stable chart identity. */}}
{{- define "goconsumerPrimordial.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/* The one and only service-tree label/annotation prefix (R16/B26). */}}
{{- define "goconsumerPrimordial.labelPrefix" -}}
{{- required "labelPrefix is required" .Values.labelPrefix | trimSuffix "/" -}}
{{- end -}}

{{/* Validate the LPSM projection before anything renders. */}}
{{- define "goconsumerPrimordial.validateServiceTree" -}}
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
{{- define "goconsumerPrimordial.resourceName" -}}
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
{{- define "goconsumerPrimordial.grafanaPrefix" -}}
{{- printf "%s-%s" .Values.serviceTree.platform .Values.serviceTree.service -}}
{{- end -}}

{{/* The service folder uid. The `-folder` suffix keeps it out of the shared
     dashboard/alert-group uid pool. */}}
{{- define "goconsumerPrimordial.grafanaFolderUid" -}}
{{- printf "%s-folder" (include "goconsumerPrimordial.grafanaPrefix" .) -}}
{{- end -}}

{{/* Service-tree labels only; every key is prefixed by labelPrefix. */}}
{{- define "goconsumerPrimordial.serviceTreeLabels" -}}
{{- $prefix := include "goconsumerPrimordial.labelPrefix" . -}}
{{- range $key, $value := .Values.serviceTree }}
{{ printf "%s/%s" $prefix $key }}: {{ $value | quote }}
{{- end }}
{{- end -}}

{{/* Labels for every owned resource. */}}
{{- define "goconsumerPrimordial.labels" -}}
helm.sh/chart: {{ include "goconsumerPrimordial.chart" . }}
app.kubernetes.io/name: {{ .Values.serviceTree.service | quote }}
app.kubernetes.io/instance: {{ .Release.Name | quote }}
app.kubernetes.io/component: primordial
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: {{ .Values.serviceTree.platform | quote }}
{{- include "goconsumerPrimordial.serviceTreeLabels" . }}
{{- end -}}

{{/* Service-tree annotations for every owned resource. */}}
{{- define "goconsumerPrimordial.annotations" -}}
{{ include "goconsumerPrimordial.serviceTreeLabels" . | trim }}
{{- end -}}

{{/* The LPSM labels merged into every alert rule. The observability standard is
     explicit that authors never hand-write these — the renderer injects them
     (Contract 1). Only the plain service-tree slots are projected: alert routing
     matches on unprefixed `platform`/`service`/`module`/`landscape`/`severity`. */}}
{{- define "goconsumerPrimordial.alertLabels" -}}
{{- range $key, $value := .Values.serviceTree }}
{{ $key }}: {{ $value | quote }}
{{- end }}
{{- end -}}
