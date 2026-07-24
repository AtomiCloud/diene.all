{{/* Chart identity. */}}
{{- define "diene-chlorine.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/* The one and only service-tree label/annotation prefix (propagated via global). */}}
{{- define "diene-chlorine.labelPrefix" -}}
{{- required "global.labelPrefix is required" .Values.global.labelPrefix | trimSuffix "/" -}}
{{- end -}}

{{/*
Validate the LPSM projection. The platform slot is rendered directly from
.Release.Namespace (see the platform label/annotation in values.yaml), so a values
file cannot stamp another platform. Required input slots are service/module/layer;
landscape and cluster arrive from independent overlays. Returns empty so the label
helper can append the namespace-sourced platform value.
*/}}
{{- define "diene-chlorine.validateServiceTree" -}}
{{- $st := required "global.serviceTree is required" .Values.global.serviceTree -}}
{{- $_ := required "global.serviceTree.service is required" $st.service -}}
{{- $_ = required "global.serviceTree.module is required" $st.module -}}
{{- $_ = required "global.serviceTree.layer is required" $st.layer -}}
{{- "" -}}
{{- end -}}

{{/* Normalize an arbitrary physical instance id into one DNS-1123 label. */}}
{{- define "diene-chlorine.instanceLabel" -}}
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
