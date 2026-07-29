{{- define "mercuryPrimordial.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" }}
app.kubernetes.io/name: webhook
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/component: primordial
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: mercury
{{- range $key, $value := .Values.serviceTree }}
{{ $.Values.labelPrefix }}/{{ $key }}: {{ $value | quote }}
{{- end }}
{{- end -}}
