{{/* Stable app-chart identity. */}}
{{- define "carbon.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/* The single label/annotation prefix. */}}
{{- define "carbon.labelPrefix" -}}
{{- required "labelPrefix is required" .Values.labelPrefix | trimSuffix "/" -}}
{{- end -}}

{{/* Validate fixed Carbon identity without emitting text. */}}
{{- define "carbon.validateServiceTree" -}}
{{- $platform := required "serviceTree.platform is required" .Values.serviceTree.platform -}}
{{- $service := required "serviceTree.service is required" .Values.serviceTree.service -}}
{{- $module := required "serviceTree.module is required" .Values.serviceTree.module -}}
{{- $layer := required "serviceTree.layer is required" .Values.serviceTree.layer -}}
{{- if ne $service "carbon" -}}{{- fail "serviceTree.service must be carbon" -}}{{- end -}}
{{- if ne $module "platform" -}}{{- fail "serviceTree.module must be platform" -}}{{- end -}}
{{- if ne $layer "1" -}}{{- fail "serviceTree.layer must be 1" -}}{{- end -}}
{{- end -}}

{{/* Common LPSM labels. */}}
{{- define "carbon.labels" -}}
{{- $prefix := include "carbon.labelPrefix" . -}}
helm.sh/chart: {{ include "carbon.chart" . }}
app.kubernetes.io/name: let__platform__-carbon
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: carbon
{{- range $key, $value := .Values.serviceTree }}
{{ printf "%s/%s" $prefix $key }}: {{ $value | quote }}
{{- end }}
{{- end -}}

{{/* Service-tree annotations mirror the projection. */}}
{{- define "carbon.annotations" -}}
{{- $prefix := include "carbon.labelPrefix" . -}}
{{- range $key, $value := .Values.serviceTree }}
{{ printf "%s/%s" $prefix $key }}: {{ $value | quote }}
{{- end }}
{{- end -}}
