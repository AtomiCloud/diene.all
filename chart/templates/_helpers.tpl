{{/* Stable chart identity. */}}
{{- define "chlorine.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/* The one and only service-tree label/annotation prefix. */}}
{{- define "chlorine.labelPrefix" -}}
{{- required "global.labelPrefix is required" .Values.global.labelPrefix | trimSuffix "/" -}}
{{- end -}}

{{/* Validate namespace-sourced platform identity and the values-owned LSM slots. */}}
{{- define "chlorine.validateServiceTree" -}}
{{- $serviceTree := required "global.serviceTree is required" .Values.global.serviceTree -}}
{{- if hasKey $serviceTree "platform" -}}
{{- fail "global.serviceTree.platform is forbidden; platform is sourced from the release namespace" -}}
{{- end -}}
{{- $_ := required "global.serviceTree.service is required" $serviceTree.service -}}
{{- $_ = required "global.serviceTree.module is required" $serviceTree.module -}}
{{- $_ = required "global.serviceTree.layer is required" $serviceTree.layer -}}
{{- end -}}

{{/* Normalize an arbitrary physical instance id into one DNS-1123 label. */}}
{{- define "chlorine.instanceLabel" -}}
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
{{- define "chlorine.resourceName" -}}
{{- $root := .root -}}
{{- $service := required "global.serviceTree.service is required" $root.Values.global.serviceTree.service | lower -}}
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

{{/* Service-tree labels only; every key uses labelPrefix. */}}
{{- define "chlorine.serviceTreeLabels" -}}
{{- $prefix := include "chlorine.labelPrefix" . -}}
{{- $serviceTree := required "global.serviceTree is required" .Values.global.serviceTree -}}
{{ printf "%s/platform" $prefix }}: {{ .Release.Namespace | quote }}
{{- range $key, $value := $serviceTree }}
{{ printf "%s/%s" $prefix $key }}: {{ $value | quote }}
{{- end }}
{{- end -}}

{{/* Service-tree and reversible instance metadata annotations. */}}
{{- define "chlorine.serviceTreeAnnotations" -}}
{{- $prefix := include "chlorine.labelPrefix" . -}}
{{- include "chlorine.serviceTreeLabels" . }}
{{- with .Values.global.instance.physicalId }}
{{ printf "%s/instance-original" $prefix }}: {{ . | quote }}
{{ printf "%s/instance-label" $prefix }}: {{ include "chlorine.instanceLabel" . | quote }}
{{- end }}
{{- end -}}

{{/* Labels for the wrapper-owned LPSM projection resource. */}}
{{- define "chlorine.labels" -}}
helm.sh/chart: {{ include "chlorine.chart" . }}
app.kubernetes.io/name: {{ include "chlorine.resourceName" (dict "root" . "token" "lpsm") }}
{{ include "chlorine.serviceTreeLabels" . }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}
