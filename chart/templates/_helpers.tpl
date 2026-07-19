{{/* Stable chart identity. */}}
{{- define "sulfur.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/* The one and only service-tree label/annotation prefix. */}}
{{- define "sulfur.labelPrefix" -}}
{{- required "labelPrefix is required" .Values.labelPrefix | trimSuffix "/" -}}
{{- end -}}

{{/* Validate the base LPSM projection. Platform must equal the release namespace. */}}
{{- define "sulfur.validateServiceTree" -}}
{{- $platform := required "serviceTree.platform is required" .Values.serviceTree.platform -}}
{{- required "serviceTree.service is required" .Values.serviceTree.service -}}
{{- required "serviceTree.module is required" .Values.serviceTree.module -}}
{{- required "serviceTree.layer is required" .Values.serviceTree.layer -}}
{{- if ne $platform .Release.Namespace -}}
{{- fail (printf "serviceTree.platform %q must equal release namespace %q" $platform .Release.Namespace) -}}
{{- end -}}
{{- end -}}

{{/* Canonical LPSM identity labels. Mirrored statically into upstream.global.commonLabels because
     subchart values cannot call templates; the labels drift-check proves they stay in sync. */}}
{{- define "sulfur.identityLabels" -}}
{{- $prefix := include "sulfur.labelPrefix" . -}}
{{ printf "%s/service" $prefix }}: {{ .Values.serviceTree.service | quote }}
{{ printf "%s/module" $prefix }}: {{ .Values.serviceTree.module | quote }}
{{ printf "%s/layer" $prefix }}: {{ .Values.serviceTree.layer | quote }}
{{ printf "%s/platform" $prefix }}: {{ .Values.serviceTree.platform | quote }}
{{- end -}}
