{{/* ### nextjs-frontend-primordial-helpers */}}
{{/* #### source: nextjs-frontend */}}

{{/* Stable chart identity. */}}
{{- define "nextjsPrimordial.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/* The one and only service-tree label/annotation prefix (R16/B26). */}}
{{- define "nextjsPrimordial.labelPrefix" -}}
{{- required "labelPrefix is required" .Values.labelPrefix | trimSuffix "/" -}}
{{- end -}}

{{/* Validate the LPSM projection before anything renders. The service slot of
     this template carries a dash (`nextjs-frontend`), so every slot is checked
     as a DNS-1123 label rather than a dash-less token: resource names stay
     `<service>-<token>` and remain valid object names either way. */}}
{{- define "nextjsPrimordial.validateServiceTree" -}}
{{- $serviceTree := required "serviceTree is required" .Values.serviceTree -}}
{{- range $slot := (list "platform" "service" "module") -}}
{{- $value := required (printf "serviceTree.%s is required" $slot) (get $serviceTree $slot) -}}
{{- if not (regexMatch "^[a-z0-9]([-a-z0-9]*[a-z0-9])?$" $value) -}}
{{- fail (printf "serviceTree.%s %q must be a DNS-1123 label" $slot $value) -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/* `<service>-<token>` resource name. The token is normalized to a dash-less
     lowercase word so the name has exactly one more dash than the service slot. */}}
{{- define "nextjsPrimordial.resourceName" -}}
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
{{- define "nextjsPrimordial.grafanaPrefix" -}}
{{- printf "%s-%s" .Values.serviceTree.platform .Values.serviceTree.service -}}
{{- end -}}

{{/* The service folder uid. The `-folder` suffix keeps it out of the shared
     dashboard/alert-group uid pool. */}}
{{- define "nextjsPrimordial.grafanaFolderUid" -}}
{{- printf "%s-folder" (include "nextjsPrimordial.grafanaPrefix" .) -}}
{{- end -}}

{{/* Service-tree labels only; every key is prefixed by labelPrefix. */}}
{{- define "nextjsPrimordial.serviceTreeLabels" -}}
{{- $prefix := include "nextjsPrimordial.labelPrefix" . -}}
{{- range $key, $value := .Values.serviceTree }}
{{ printf "%s/%s" $prefix $key }}: {{ $value | quote }}
{{- end }}
{{- end -}}

{{/* Labels for every owned resource. */}}
{{- define "nextjsPrimordial.labels" -}}
helm.sh/chart: {{ include "nextjsPrimordial.chart" . }}
app.kubernetes.io/name: {{ .Values.serviceTree.service | quote }}
app.kubernetes.io/instance: {{ .Release.Name | quote }}
app.kubernetes.io/component: primordial
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: {{ .Values.serviceTree.platform | quote }}
{{- include "nextjsPrimordial.serviceTreeLabels" . }}
{{- end -}}

{{/* Service-tree annotations for every owned resource. */}}
{{- define "nextjsPrimordial.annotations" -}}
{{ include "nextjsPrimordial.serviceTreeLabels" . | trim }}
{{- end -}}

{{/* The LPSM labels merged into every alert rule. The observability standard is
     explicit that authors never hand-write these — the renderer injects them
     (Contract 1). Only the plain service-tree slots are projected: alert routing
     matches on unprefixed `platform`/`service`/`module`/`landscape`/`severity`. */}}
{{- define "nextjsPrimordial.alertLabels" -}}
{{- range $key, $value := .Values.serviceTree }}
{{ $key }}: {{ $value | quote }}
{{- end }}
{{- end -}}
