{{/* Stable chart identity. */}}
{{- define "diene-helm-wrapper.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/* The one and only service-tree label/annotation prefix. */}}
{{- define "diene-helm-wrapper.labelPrefix" -}}
{{- required "labelPrefix is required" .Values.labelPrefix | trimSuffix "/" -}}
{{- end -}}

{{/* Validate the base LPSM projection without requiring overlay-owned fields. */}}
{{- define "diene-helm-wrapper.validateServiceTree" -}}
{{- $platform := required "serviceTree.platform is required" .Values.serviceTree.platform -}}
{{- $service := required "serviceTree.service is required" .Values.serviceTree.service -}}
{{- $module := required "serviceTree.module is required" .Values.serviceTree.module -}}
{{- $layer := required "serviceTree.layer is required" .Values.serviceTree.layer -}}
{{- if ne $platform .Release.Namespace -}}
{{- fail (printf "serviceTree.platform %q must equal release namespace %q" $platform .Release.Namespace) -}}
{{- end -}}
{{- end -}}

{{/* Normalize an arbitrary physical instance id into one DNS-1123 label. */}}
{{- define "diene-helm-wrapper.instanceLabel" -}}
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
{{- define "diene-helm-wrapper.resourceName" -}}
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

{{/* The primary workload must explicitly use fullnameOverride. */}}
{{- define "diene-helm-wrapper.primaryName" -}}
{{- $expected := include "diene-helm-wrapper.resourceName" (dict "root" . "token" "api") -}}
{{- if ne .Values.fullnameOverride $expected -}}
{{- fail (printf "fullnameOverride must be %q, got %q" $expected .Values.fullnameOverride) -}}
{{- end -}}
{{- $expected -}}
{{- end -}}

{{/* Common selector labels. */}}
{{- define "diene-helm-wrapper.selectorLabels" -}}
app.kubernetes.io/name: {{ include "diene-helm-wrapper.primaryName" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{/* Service-tree labels; every key uses labelPrefix. */}}
{{- define "diene-helm-wrapper.labels" -}}
{{- $prefix := include "diene-helm-wrapper.labelPrefix" . -}}
helm.sh/chart: {{ include "diene-helm-wrapper.chart" . }}
{{ include "diene-helm-wrapper.selectorLabels" . }}
{{- range $key, $value := .Values.serviceTree }}
{{ printf "%s/%s" $prefix $key }}: {{ $value | quote }}
{{- end }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{/* Service-tree and reversible instance metadata annotations. */}}
{{- define "diene-helm-wrapper.annotations" -}}
{{- $prefix := include "diene-helm-wrapper.labelPrefix" . -}}
{{- range $key, $value := .Values.serviceTree }}
{{ printf "%s/%s" $prefix $key }}: {{ $value | quote }}
{{- end }}
{{- with .Values.instance.physicalId }}
{{ printf "%s/instance-original" $prefix }}: {{ . | quote }}
{{ printf "%s/instance-label" $prefix }}: {{ include "diene-helm-wrapper.instanceLabel" . | quote }}
{{- end }}
{{- end -}}

{{/* Reloader is opt-in at the controller and default-on in this wrapper. */}}
{{- define "diene-helm-wrapper.reloaderAnnotations" -}}
{{- if .enabled }}
reloader.stakater.com/auto: 'true'
{{- end }}
{{- end -}}

{{/* Derive ordinary or instance-qualified dotted hostnames. Platform always comes from namespace. */}}
{{- define "diene-helm-wrapper.hostname" -}}
{{- $root := .root -}}
{{- $module := required "hostname module is required" .module | lower -}}
{{- $service := required "hostname service is required" .service | lower -}}
{{- $landscape := required "hostname landscape is required" .landscape | lower -}}
{{- $zone := required "hostname zone is required" .zone | lower | trimPrefix "." -}}
{{- $platform := $root.Release.Namespace | lower -}}
{{- $instance := default "" .instance | lower -}}
{{- range $label := list $module $service $platform $landscape }}
{{- if not (regexMatch "^[a-z0-9-]+$" $label) -}}
{{- fail (printf "hostname label %q is not DNS-compatible" $label) -}}
{{- end -}}
{{- end -}}
{{- if $instance -}}
{{- if not (regexMatch "^[a-z0-9-]+$" $instance) -}}
{{- fail (printf "hostname instance %q is not DNS-compatible" $instance) -}}
{{- end -}}
{{- printf "%s.%s.%s.%s.%s.%s" $module $service $platform $instance $landscape $zone -}}
{{- else -}}
{{- printf "%s.%s.%s.%s.%s" $module $service $platform $landscape $zone -}}
{{- end -}}
{{- end -}}

{{/* Parse a hostname back into the unchanged four-slot LPSM coordinate plus instance. */}}
{{- define "diene-helm-wrapper.parseHostname" -}}
{{- $hostname := required "hostname is required" .hostname | lower -}}
{{- $zone := required "zone is required" .zone | lower | trimPrefix "." -}}
{{- $suffix := printf ".%s" $zone -}}
{{- if not (hasSuffix $suffix $hostname) -}}
{{- fail (printf "hostname %q does not end with configured zone %q" $hostname $zone) -}}
{{- end -}}
{{- $prefix := trimSuffix $suffix $hostname -}}
{{- $parts := splitList "." $prefix -}}
{{- if eq (len $parts) 4 -}}
{{- toJson (dict "landscape" (index $parts 3) "platform" (index $parts 2) "service" (index $parts 1) "module" (index $parts 0) "instance" "") -}}
{{- else if eq (len $parts) 5 -}}
{{- toJson (dict "landscape" (index $parts 4) "platform" (index $parts 2) "service" (index $parts 1) "module" (index $parts 0) "instance" (index $parts 3)) -}}
{{- else -}}
{{- fail (printf "hostname %q must use the canonical dotted LPSM form" $hostname) -}}
{{- end -}}
{{- end -}}
