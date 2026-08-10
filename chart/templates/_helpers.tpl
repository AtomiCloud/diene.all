{{/* Stable chart identity. */}}
{{- define "diene-zinc.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/* The one and only service-tree label/annotation prefix. */}}
{{- define "diene-zinc.labelPrefix" -}}
{{- required "labelPrefix is required" .Values.labelPrefix | trimSuffix "/" -}}
{{- end -}}

{{/* Validate the LPSM projection. Platform is sourced from the release namespace,
     never a value; the values-owned slots (service/module/layer) are required. */}}
{{- define "diene-zinc.validateServiceTree" -}}
{{- $serviceTree := required "serviceTree is required" .Values.serviceTree -}}
{{- if hasKey $serviceTree "platform" -}}
{{- fail "serviceTree.platform is forbidden; platform is sourced from the release namespace" -}}
{{- end -}}
{{- $_ := required "serviceTree.service is required" $serviceTree.service -}}
{{- $_ = required "serviceTree.module is required" $serviceTree.module -}}
{{- $_ = required "serviceTree.layer is required" $serviceTree.layer -}}
{{- end -}}

{{/* Normalize an arbitrary physical instance id into one DNS-1123 label. */}}
{{- define "diene-zinc.instanceLabel" -}}
{{- $original := required "physical instance id is required" . -}}
{{- $normalized := regexReplaceAll "[^a-z0-9-]+" (lower $original) "-" -}}
{{- $normalized = regexReplaceAll "-+" $normalized "-" | trimAll "-" -}}
{{- if eq $normalized "" -}}
{{- fail "physical instance id normalizes to an empty label" -}}
{{- end -}}
{{- if le (len $normalized) 63 -}}
{{- $normalized -}}
{{- else -}}
{{- $hash := sha256sum $original | trunc 8 -}}
{{- $prefix := trunc 54 $normalized | trimSuffix "-" -}}
{{- printf "%s-%s" $prefix $hash -}}
{{- end -}}
{{- end -}}

{{/* Build an exactly-one-dash resource name from service + fused token. */}}
{{- define "diene-zinc.resourceName" -}}
{{- $root := .root -}}
{{- $service := required "serviceTree.service is required" $root.Values.serviceTree.service | lower -}}
{{- $token := required "resource token is required" .token | lower -}}
{{- $token = regexReplaceAll "[^a-z0-9]+" $token "" -}}
{{- if not (regexMatch "^[a-z0-9]+$" $service) -}}
{{- fail (printf "service %q must be dash-less lowercase alphanumeric" $service) -}}
{{- end -}}
{{- if not (regexMatch "^[a-z0-9]+$" $token) -}}
{{- fail (printf "token %q must normalize to a dash-less lowercase token" .token) -}}
{{- end -}}
{{- printf "%s-%s" $service $token -}}
{{- end -}}

{{/* Service-tree labels only; every key uses labelPrefix. Platform is the release
     namespace and is never a value. */}}
{{- define "diene-zinc.serviceTreeLabels" -}}
{{- $prefix := include "diene-zinc.labelPrefix" . -}}
{{- $serviceTree := required "serviceTree is required" .Values.serviceTree -}}
{{ printf "%s/platform" $prefix }}: {{ .Release.Namespace | quote }}
{{- range $key, $value := $serviceTree }}
{{ printf "%s/%s" $prefix $key }}: {{ $value | quote }}
{{- end }}
{{- end -}}

{{/* Labels for zinc's own resources. */}}
{{- define "diene-zinc.labels" -}}
helm.sh/chart: {{ include "diene-zinc.chart" . }}
app.kubernetes.io/name: {{ .Values.serviceTree.service | quote }}
app.kubernetes.io/instance: {{ .Release.Name | quote }}
{{ include "diene-zinc.serviceTreeLabels" . }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{/* Service-tree and reversible instance metadata annotations. */}}
{{- define "diene-zinc.annotations" -}}
{{- $prefix := include "diene-zinc.labelPrefix" . -}}
{{- include "diene-zinc.serviceTreeLabels" . }}
{{- with .Values.instance.physicalId }}
{{ printf "%s/instance-original" $prefix }}: {{ . | quote }}
{{ printf "%s/instance-label" $prefix }}: {{ include "diene-zinc.instanceLabel" . | quote }}
{{- end }}
{{- end -}}
