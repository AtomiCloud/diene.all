{{- define "mercury.name" -}}webhook{{- end -}}
{{- define "mercury.fullname" -}}{{ .Values.serviceTree.service }}-{{ .Values.serviceTree.module }}{{- end -}}
{{- define "mercury.selectorLabels" -}}
app.kubernetes.io/name: {{ include "mercury.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/component: {{ .Values.serviceTree.module }}
{{- end -}}
{{- define "mercury.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" }}
{{ include "mercury.selectorLabels" . }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: {{ .Values.serviceTree.platform }}
{{- range $key, $value := .Values.serviceTree }}
{{ $.Values.labelPrefix }}/{{ $key }}: {{ $value | quote }}
{{- end }}
{{- end -}}
{{- define "mercury.image" -}}
{{- $tag := .Values.image.tag | default .Chart.AppVersion -}}
{{- if eq (toString $tag) "latest" }}{{ fail "latest image tags are forbidden" }}{{ end -}}
{{ printf "%s:%s" .Values.image.repository $tag }}
{{- end -}}
