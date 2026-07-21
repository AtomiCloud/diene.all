{{- define "carbonPrimordial.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "carbonPrimordial.labelPrefix" -}}
{{- required "labelPrefix is required" .Values.labelPrefix | trimSuffix "/" -}}
{{- end -}}

{{- define "carbonPrimordial.validateServiceTree" -}}
{{- $platform := required "serviceTree.platform is required" .Values.serviceTree.platform -}}
{{- if ne .Values.serviceTree.service "carbon" -}}{{- fail "serviceTree.service must be carbon" -}}{{- end -}}
{{- if ne .Values.serviceTree.module "platformdeps" -}}{{- fail "serviceTree.module must be platformdeps" -}}{{- end -}}
{{- if ne .Values.serviceTree.layer "1" -}}{{- fail "serviceTree.layer must be 1" -}}{{- end -}}
{{- end -}}

{{- define "carbonPrimordial.labels" -}}
{{- $prefix := include "carbonPrimordial.labelPrefix" . -}}
helm.sh/chart: {{ include "carbonPrimordial.chart" . }}
app.kubernetes.io/name: diene-carbon-primordial
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: carbon
{{- range $key, $value := .Values.serviceTree }}
{{ printf "%s/%s" $prefix $key }}: {{ $value | quote }}
{{- end }}
{{- end -}}

{{- define "carbonPrimordial.annotations" -}}
{{- $prefix := include "carbonPrimordial.labelPrefix" . -}}
{{- range $key, $value := .Values.serviceTree }}
{{ printf "%s/%s" $prefix $key }}: {{ $value | quote }}
{{- end }}
{{- end -}}
