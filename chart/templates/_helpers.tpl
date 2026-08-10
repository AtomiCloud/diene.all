{{- define "lithium.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "lithium.labelPrefix" -}}{{ required "labelPrefix is required" .Values.labelPrefix | trimSuffix "/" }}{{- end -}}

{{- define "lithium.mode" -}}
{{- $mode := required "distributionMode is required" .Values.distributionMode -}}
{{- if not (has $mode (list "FLEET" "GARDEN-LOCAL")) -}}{{ fail "distributionMode must be FLEET or GARDEN-LOCAL" }}{{- end -}}
{{- $mode -}}
{{- end -}}

{{- define "lithium.validate" -}}
{{- $_ := include "lithium.mode" . -}}
{{- range $key := list "platform" "service" "module" "layer" "landscape" -}}{{- $_ := required (printf "serviceTree.%s is required" $key) (get $.Values.serviceTree $key) -}}{{- end -}}
{{- if ne .Values.serviceTree.service "lithium" }}{{ fail "serviceTree.service must be lithium" }}{{ end -}}
{{- if ne .Values.serviceTree.module "api" }}{{ fail "serviceTree.module must be api" }}{{ end -}}
{{- if eq .Values.distributionMode "GARDEN-LOCAL" -}}
{{- range $key := list "instance" "instanceUID" "allocationGeneration" "landscape" "zone" "issuerScheme" "issuerPort" -}}{{- $_ := required (printf "garden.%s is required for GARDEN-LOCAL" $key) (get $.Values.garden $key) -}}{{- end -}}
{{- range $key := list "databaseSecret" "databaseKey" "bootSecret" "bootClientIdKey" "bootClientSecretKey" -}}{{- $_ := required (printf "garden.%s is required for GARDEN-LOCAL" $key) (get $.Values.garden $key) -}}{{- end -}}
{{- if eq .Values.garden.issuerScheme "http" -}}
{{- if or (ne .Values.garden.zone "localhost") (le (.Values.garden.issuerPort | int) 0) -}}{{ fail "local Garden issuer requires http, localhost, and issuerPort" }}{{- end -}}
{{- else if eq .Values.garden.issuerScheme "https" -}}
{{- if ne (.Values.garden.issuerPort | int) 0 -}}{{ fail "HTTPS Garden issuer must not carry a local port" }}{{- end -}}
{{- else -}}{{ fail "garden.issuerScheme must be http or https" }}{{- end -}}
{{- end -}}
{{- end -}}

{{- define "lithium.name" -}}lithium-api{{- end -}}
{{- define "lithium.selectorLabels" -}}
app.kubernetes.io/name: {{ include "lithium.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}
{{- define "lithium.labels" -}}
{{- $prefix := include "lithium.labelPrefix" . -}}
helm.sh/chart: {{ include "lithium.chart" . }}
{{ include "lithium.selectorLabels" . }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: lithium
{{- range $key, $value := .Values.serviceTree }}
{{ printf "%s/%s" $prefix $key }}: {{ $value | quote }}
{{- end }}
{{- if eq .Values.distributionMode "GARDEN-LOCAL" }}
{{ printf "%s/instance" $prefix }}: {{ .Values.garden.instance | quote }}
{{ printf "%s/instance-uid" $prefix }}: {{ .Values.garden.instanceUID | quote }}
{{ printf "%s/allocation-generation" $prefix }}: {{ .Values.garden.allocationGeneration | quote }}
{{- end }}
{{- end -}}
{{- define "lithium.annotations" -}}
{{- $prefix := include "lithium.labelPrefix" . -}}
{{- range $key, $value := .Values.serviceTree }}
{{ printf "%s/%s" $prefix $key }}: {{ $value | quote }}
{{- end }}
{{- end -}}
{{- define "lithium.imageRef" -}}
{{- if .Values.image.digest -}}{{ printf "%s@%s" .Values.image.repository .Values.image.digest }}{{- else -}}{{ printf "%s:%s" .Values.image.repository .Values.image.tag }}{{- end -}}
{{- end -}}
{{- define "lithium.bootPath" -}}{{ printf "/%s/lithium" .Values.serviceTree.platform }}{{- end -}}
{{- define "lithium.issuer" -}}
{{- if eq .Values.distributionMode "FLEET" -}}
{{ printf "https://api.lithium.%s.%s.%s" .Values.serviceTree.platform .Values.fleet.vlandscape .Values.fleet.issuerZone }}
{{- else -}}
{{- if eq .Values.garden.issuerScheme "http" -}}
{{ printf "http://api.lithium.%s.%s.%s.localhost:%d" .Values.serviceTree.platform .Values.garden.instance .Values.garden.landscape (.Values.garden.issuerPort | int) }}
{{- else -}}
{{ printf "https://api.lithium.%s.%s.%s.%s" .Values.serviceTree.platform .Values.garden.instance .Values.garden.landscape .Values.garden.zone }}
{{- end -}}
{{- end -}}
{{- end -}}
