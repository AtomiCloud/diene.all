{{- define "lithiumPrimordial.prefix" -}}{{ required "labelPrefix is required" .Values.labelPrefix | trimSuffix "/" }}{{- end -}}
{{- define "lithiumPrimordial.validate" -}}
{{- $mode := required "distributionMode is required" .Values.distributionMode -}}
{{- if not (has $mode (list "FLEET" "GARDEN-LOCAL")) }}{{ fail "distributionMode must be FLEET or GARDEN-LOCAL" }}{{ end -}}
{{- if ne .Values.serviceTree.service "lithium" }}{{ fail "serviceTree.service must be lithium" }}{{ end -}}
{{- if ne .Values.serviceTree.module "api" }}{{ fail "serviceTree.module must be api" }}{{ end -}}
{{- end -}}
{{- define "lithiumPrimordial.labels" -}}
{{- $prefix := include "lithiumPrimordial.prefix" . -}}
app.kubernetes.io/name: diene-lithium-primordial
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/part-of: lithium
{{- range $key, $value := .Values.serviceTree }}
{{ printf "%s/%s" $prefix $key }}: {{ $value | quote }}
{{- end }}
{{- end -}}
