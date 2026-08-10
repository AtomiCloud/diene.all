{{/* Stable chart identity. */}}
{{- define "cobalt.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/* The one and only service-tree label/annotation prefix. */}}
{{- define "cobalt.labelPrefix" -}}
{{- required "labelPrefix is required" .Values.labelPrefix | trimSuffix "/" -}}
{{- end -}}

{{/* Validate the layer-1 service-tree projection.

cobalt is cluster-wide layer-1 infrastructure, not a service inside a platform
namespace, so the platform slot is a layer-1 scope marker rather than the
release namespace (the wrapper's namespace binding is intentionally relaxed). */}}
{{/* Validate the layer-1 service-tree projection without emitting any text.

`required` returns its value, so every call is captured into a variable to keep
this helper emission-free (it is invoked via `include` immediately before the
apiVersion line of the ClusterSecretStore). */}}
{{- define "cobalt.validateServiceTree" -}}
{{- $platform := required "serviceTree.platform is required" .Values.serviceTree.platform -}}
{{- $service := required "serviceTree.service is required" .Values.serviceTree.service -}}
{{- $module := required "serviceTree.module is required" .Values.serviceTree.module -}}
{{- $layer := required "serviceTree.layer is required" .Values.serviceTree.layer -}}
{{- if ne $service "cobalt" -}}
{{- fail (printf "cobalt chart serviceTree.service must be %q, got %q" "cobalt" $service) -}}
{{- end -}}
{{- if ne $module "sos" -}}
{{- fail (printf "cobalt chart serviceTree.module must be %q, got %q" "sos" $module) -}}
{{- end -}}
{{- if ne $layer "1" -}}
{{- fail (printf "cobalt chart serviceTree.layer must be %q, got %q" "1" $layer) -}}
{{- end -}}
{{- end -}}

{{/* Build an exactly-one-dash resource name from service + fused token. */}}
{{- define "cobalt.resourceName" -}}
{{- $root := .root -}}
{{- $service := required "serviceTree.service is required" $root.Values.serviceTree.service | lower -}}
{{- $token := required "resource token is required" .token | lower -}}
{{- $token = regexReplaceAll "[^a-z0-9]+" $token "" -}}
{{- if not (regexMatch "^[a-z0-9]+$" $token) -}}
{{- fail (printf "token %q must normalize to a dash-less lowercase token" .token) -}}
{{- end -}}
{{- printf "%s-%s" $service $token -}}
{{- end -}}

{{/* The ClusterSecretStore fullname must be cobalt-sos. */}}
{{- define "cobalt.primaryName" -}}
{{- $expected := include "cobalt.resourceName" (dict "root" . "token" "sos") -}}
{{- if ne .Values.fullnameOverride $expected -}}
{{- fail (printf "fullnameOverride must be %q, got %q" $expected .Values.fullnameOverride) -}}
{{- end -}}
{{- $expected -}}
{{- end -}}

{{/* Common Kubernetes labels. */}}
{{- define "cobalt.labels" -}}
{{- $prefix := include "cobalt.labelPrefix" . -}}
{{- $name := include "cobalt.primaryName" . -}}
helm.sh/chart: {{ include "cobalt.chart" . }}
app.kubernetes.io/name: {{ $name }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: cobalt
{{- range $key, $value := .Values.serviceTree }}
{{ printf "%s/%s" $prefix $key }}: {{ $value | quote }}
{{- end }}
{{- end -}}

{{/* Service-tree annotations mirroring the labels. */}}
{{- define "cobalt.annotations" -}}
{{- $prefix := include "cobalt.labelPrefix" . -}}
{{- range $key, $value := .Values.serviceTree }}
{{ printf "%s/%s" $prefix $key }}: {{ $value | quote }}
{{- end }}
{{- end -}}
