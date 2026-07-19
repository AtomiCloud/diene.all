{{/* Stable chart identity. */}}
{{- define "diene-charts-aluminium.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/* The one and only service-tree label/annotation prefix. */}}
{{- define "diene-charts-aluminium.labelPrefix" -}}
{{- required "global.labelPrefix is required" .Values.global.labelPrefix | trimSuffix "/" -}}
{{- end -}}

{{/* Validate the base LPSM projection; platform must equal release namespace. */}}
{{- define "diene-charts-aluminium.validateServiceTree" -}}
{{- $platform := required "serviceTree.platform is required" .Values.serviceTree.platform -}}
{{- $service := required "serviceTree.service is required" .Values.serviceTree.service -}}
{{- $module := required "serviceTree.module is required" .Values.serviceTree.module -}}
{{- $layer := required "serviceTree.layer is required" .Values.serviceTree.layer -}}
{{- if ne $platform .Release.Namespace -}}
{{- fail (printf "serviceTree.platform %q must equal release namespace %q" $platform .Release.Namespace) -}}
{{- end -}}
{{- end -}}

{{/* Normalize an arbitrary physical instance id into one DNS-1123 label. */}}
{{- define "diene-charts-aluminium.instanceLabel" -}}
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
{{- define "diene-charts-aluminium.resourceName" -}}
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

{{/* Service-tree labels; every key uses labelPrefix. */}}
{{- define "diene-charts-aluminium.labels" -}}
{{- $prefix := include "diene-charts-aluminium.labelPrefix" . -}}
helm.sh/chart: {{ include "diene-charts-aluminium.chart" . }}
app.kubernetes.io/name: {{ .Values.serviceTree.service }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- range $key, $value := .Values.serviceTree }}
{{ printf "%s/%s" $prefix $key }}: {{ $value | quote }}
{{- end }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{/* Service-tree annotations (every key uses labelPrefix). */}}
{{- define "diene-charts-aluminium.annotations" -}}
{{- $prefix := include "diene-charts-aluminium.labelPrefix" . -}}
{{- range $key, $value := .Values.serviceTree }}
{{ printf "%s/%s" $prefix $key }}: {{ $value | quote }}
{{- end }}
{{- end -}}

{{/*
Extend the upstream collector-value bridge with the shared global labelPrefix.
The dependency intentionally exposes collector labels as values, but Helm does
not template values keys. These two namespaced overrides convert suffix-only
collector label keys into fully qualified keys while preserving upstream image
and pod-security global handling.
*/}}
{{- define "collector.alloy.values.global" }}
{{- $globalValues := dict }}
{{- if dig "image" "registry" "" .Values.global }}
  {{- $globalValues = mergeOverwrite $globalValues (dict "global" (dict "image" (dict "registry" .Values.global.image.registry))) }}
{{- end }}
{{- if dig "image" "pullSecrets" "" .Values.global }}
  {{- $globalValues = mergeOverwrite $globalValues (dict "global" (dict "image" (dict "pullSecrets" .Values.global.image.pullSecrets))) }}
{{- end }}
{{- if dig "image" "pullPolicy" "" .Values.global }}
  {{- $globalValues = mergeOverwrite $globalValues (dict "global" (dict "image" (dict "pullPolicy" .Values.global.image.pullPolicy))) }}
{{- end }}
{{- if dig "podSecurityContext" "" .Values.global }}
  {{- $globalValues = mergeOverwrite $globalValues (dict "global" (dict "podSecurityContext" .Values.global.podSecurityContext)) }}
{{- end }}
{{- if dig "labelPrefix" "" .Values.global }}
  {{- $globalValues = mergeOverwrite $globalValues (dict "global" (dict "labelPrefix" .Values.global.labelPrefix)) }}
{{- end }}
{{- $globalValues | toYaml }}
{{- end }}

{{- define "collector.alloy.valuesToSpec" }}
{{- $values := deepCopy . }}
{{- $prefix := dig "global" "labelPrefix" "" $values | trimSuffix "/" }}
{{- if $prefix }}
  {{- $labels := dig "alloy" "labels" (dict) $values }}
  {{- $qualifiedLabels := dict }}
  {{- range $key, $value := $labels }}
    {{- $qualifiedKey := $key }}
    {{- if not (contains "/" $key) }}
      {{- $qualifiedKey = printf "%s/%s" $prefix $key }}
    {{- end }}
    {{- $_ := set $qualifiedLabels $qualifiedKey $value }}
  {{- end }}
  {{- $_ := set $values.alloy "labels" $qualifiedLabels }}
  {{- $_ := unset $values.global "labelPrefix" }}
  {{- if eq (len $values.global) 0 }}
    {{- $_ := unset $values "global" }}
  {{- end }}
{{- end }}
{{- $fieldsToExclude := include "collector.alloy.extraFields" $values | fromYamlArray }}
{{- $cleanValues := dict }}
{{- range $key, $value := $values }}
  {{- if not (has $key $fieldsToExclude) }}
    {{- $_ := set $cleanValues $key $value }}
  {{- end }}
{{- end }}
{{- $cleanValues | toYaml }}
{{- end }}
