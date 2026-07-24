{{- define "operator-template.fullname" -}}
{{- .Release.Name -}}
{{- end -}}

{{- define "operator-template.serviceAccountName" -}}
{{- default (include "operator-template.fullname" .) .Values.serviceAccount.name -}}
{{- end -}}

{{- define "operator-template.scraperName" -}}
{{- default (printf "%s-metrics-reader" (include "operator-template.fullname" .)) .Values.serviceMonitor.scraper.serviceAccountName -}}
{{- end -}}

{{- define "operator-template.image" -}}
{{- printf "%s:%s" .Values.image.repository (.Values.image.tag | default .Chart.AppVersion) -}}
{{- end -}}

{{- define "operator-template.selectorLabels" -}}
app.kubernetes.io/name: operator-template
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "operator-template.labels" -}}
app.kubernetes.io/name: operator-template
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version }}
{{- end -}}
