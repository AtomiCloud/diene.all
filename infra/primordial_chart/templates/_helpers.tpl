{{/* ### dotnet-api-primordial-helpers */}}
{{/* #### source: dotnet-api */}}

{{/* Stable chart identity. */}}
{{- define "dotnetapiPrimordial.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/* The one and only service-tree label/annotation prefix (R16/B26). */}}
{{- define "dotnetapiPrimordial.labelPrefix" -}}
{{- required "labelPrefix is required" .Values.labelPrefix | trimSuffix "/" -}}
{{- end -}}

{{/* Validate the LPSM projection before anything renders. */}}
{{- define "dotnetapiPrimordial.validateServiceTree" -}}
{{- $serviceTree := required "serviceTree is required" .Values.serviceTree -}}
{{- range $key := (list "platform" "service" "module" "landscape") -}}
{{- $value := required (printf "serviceTree.%s is required" $key) (get $serviceTree $key) -}}
{{- if not (regexMatch "^[a-z0-9]([-a-z0-9]*[a-z0-9])?$" $value) -}}
{{- fail (printf "serviceTree.%s %q must be a DNS-1123 label" $key $value) -}}
{{- end -}}
{{- end -}}
{{- $_ := required "serviceTree.layer is required" $serviceTree.layer -}}
{{- end -}}

{{/* Build a resource name as `<service>-<token>`. */}}
{{- define "dotnetapiPrimordial.resourceName" -}}
{{- $root := .root -}}
{{- $service := required "serviceTree.service is required" $root.Values.serviceTree.service | lower -}}
{{- $token := required "resource token is required" .token | lower -}}
{{- if not (regexMatch "^[a-z0-9]+$" $token) -}}
{{- fail (printf "token %q must be a dash-less lowercase token" .token) -}}
{{- end -}}
{{- printf "%s-%s" $service $token | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/* `<platform>-<service>` — the prefix every deterministic Grafana uid is built from
     (observability standard, Contract 2). */}}
{{- define "dotnetapiPrimordial.grafanaPrefix" -}}
{{- printf "%s-%s" .Values.serviceTree.platform .Values.serviceTree.service -}}
{{- end -}}

{{/* The service folder uid. The `-folder` suffix keeps it out of the shared dashboard and
     alert-group uid pool. */}}
{{- define "dotnetapiPrimordial.grafanaFolderUid" -}}
{{- printf "%s-folder" (include "dotnetapiPrimordial.grafanaPrefix" .) -}}
{{- end -}}

{{/* Service-tree labels only; every key is prefixed by labelPrefix. */}}
{{- define "dotnetapiPrimordial.serviceTreeLabels" -}}
{{- $prefix := include "dotnetapiPrimordial.labelPrefix" . -}}
{{- range $key, $value := .Values.serviceTree }}
{{ printf "%s/%s" $prefix $key }}: {{ $value | quote }}
{{- end }}
{{- end -}}

{{/* Labels for every owned resource. */}}
{{- define "dotnetapiPrimordial.labels" -}}
helm.sh/chart: {{ include "dotnetapiPrimordial.chart" . }}
app.kubernetes.io/name: {{ .Values.serviceTree.service | quote }}
app.kubernetes.io/instance: {{ .Release.Name | quote }}
app.kubernetes.io/component: primordial
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: {{ .Values.serviceTree.platform | quote }}
{{- include "dotnetapiPrimordial.serviceTreeLabels" . }}
{{- end -}}

{{/* Service-tree annotations for every owned resource. */}}
{{- define "dotnetapiPrimordial.annotations" -}}
{{ include "dotnetapiPrimordial.serviceTreeLabels" . | trim }}
{{- end -}}

{{/* The LPSM labels merged into every alert rule. The observability standard is explicit that
     authors never hand-write these — the renderer injects them (Contract 1). Only the plain
     service-tree slots are projected: alert routing matches on unprefixed
     platform/service/module/landscape/severity. */}}
{{- define "dotnetapiPrimordial.alertLabels" -}}
{{- range $key, $value := .Values.serviceTree }}
{{ $key }}: {{ $value | quote }}
{{- end }}
{{- end -}}

{{/* Validate one declared LogtoApp path. Paths are declared; redirect URIs are DERIVED by the
     operator from the live serve-set, so anything resembling an authority, query, fragment,
     dot segment, or percent-encoded separator is a chart authoring error and not something to
     pass through to the operator. */}}
{{- define "dotnetapiPrimordial.validatePath" -}}
{{- $key := .key -}}
{{- $value := .value -}}
{{- if $value -}}
{{- if not (hasPrefix "/" $value) -}}
{{- fail (printf "logtoApp.paths.%s %q must be an absolute path beginning with one `/`" $key $value) -}}
{{- end -}}
{{- if regexMatch "^//|[?#]|(^|/)\\.{1,2}(/|$)|%2[fF]" $value -}}
{{- fail (printf "logtoApp.paths.%s %q must carry no authority, query, fragment, empty/dot segment, or percent-encoded `/`" $key $value) -}}
{{- end -}}
{{- end -}}
{{- end -}}
