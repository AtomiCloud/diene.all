{{- define "fleet-operator.fullname" -}}
{{- .Release.Name -}}
{{- end -}}

{{- define "fleet-operator.serviceAccountName" -}}
{{- default (include "fleet-operator.fullname" .) .Values.serviceAccount.name -}}
{{- end -}}

{{- define "fleet-operator.scraperName" -}}
{{- default (printf "%s-metrics-reader" (include "fleet-operator.fullname" .)) .Values.serviceMonitor.scraper.serviceAccountName -}}
{{- end -}}

{{- define "fleet-operator.image" -}}
{{- printf "%s:%s" .Values.image.repository (.Values.image.tag | default .Chart.AppVersion) -}}
{{- end -}}

{{- define "fleet-operator.selectorLabels" -}}
app.kubernetes.io/name: fleet-operator
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "fleet-operator.labels" -}}
app.kubernetes.io/name: fleet-operator
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version }}
{{- end -}}
