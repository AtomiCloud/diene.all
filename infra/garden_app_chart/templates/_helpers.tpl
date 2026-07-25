{{/* ### nextjs-frontend-garden-app-helpers */}}
{{/* #### source: nextjs-frontend */}}

{{/* Stable chart identity. */}}
{{- define "gardenApp.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/* The one and only service-tree label/annotation prefix (R16/B26). */}}
{{- define "gardenApp.labelPrefix" -}}
{{- required "labelPrefix is required" .Values.labelPrefix | trimSuffix "/" -}}
{{- end -}}

{{/* Validate LPSM + the separate instance projection before anything renders.
     `instance` is a PROJECTION PARAMETER, never a fifth LPSM slot: the schema
     forbids it inside `serviceTree` and this guard re-proves it at render time
     so a `--set serviceTree.instance=…` cannot smuggle it in. */}}
{{- define "gardenApp.validateIdentity" -}}
{{- $serviceTree := required "serviceTree is required" .Values.serviceTree -}}
{{- range $slot := (list "landscape" "platform" "service" "module") -}}
{{- $value := required (printf "serviceTree.%s is required" $slot) (get $serviceTree $slot) -}}
{{- if not (regexMatch "^[a-z0-9]([-a-z0-9]*[a-z0-9])?$" $value) -}}
{{- fail (printf "serviceTree.%s %q must be a DNS-1123 label" $slot $value) -}}
{{- end -}}
{{- end -}}
{{- if hasKey $serviceTree "instance" -}}
{{- fail "serviceTree.instance is not an LPSM slot: instance is a projection parameter and belongs at the top-level `instance` value" -}}
{{- end -}}
{{- $_ := required "instance is required (the projection parameter of the dotted surface name)" .Values.instance -}}
{{- $_ = required "zone is required" .Values.zone -}}
{{- $profile := required "profile is required" .Values.profile -}}
{{- if not (has $profile (list "lapras" "ditto" "rotom" "absol" "eevee" "plusle" "minun")) -}}
{{- fail (printf "profile %q is not one of the seven ratified Garden workload profiles" $profile) -}}
{{- end -}}
{{- if ne $profile $serviceTree.landscape -}}
{{- fail (printf "profile %q and serviceTree.landscape %q must name the same landscape" $profile $serviceTree.landscape) -}}
{{- end -}}
{{- end -}}

{{/* `<service>-<token>` resource name. The token normalizes to a dash-less
     lowercase word, so the name is a valid DNS-1123 object name. */}}
{{- define "gardenApp.resourceName" -}}
{{- $root := .root -}}
{{- $service := required "serviceTree.service is required" $root.Values.serviceTree.service | lower -}}
{{- $token := required "resource token is required" .token | lower -}}
{{- $token = regexReplaceAll "[^a-z0-9]+" $token "" -}}
{{- if not (regexMatch "^[a-z0-9]+$" $token) -}}
{{- fail (printf "token %q must normalize to a dash-less lowercase token" .token) -}}
{{- end -}}
{{- printf "%s-%s" $service $token -}}
{{- end -}}

{{/* The canonical dotted surface name
     `<module>.<service>.<platform>.<instance>.<landscape>.<zone>`. Dash-fused
     aliases are invalid, so this is assembled from the slots and never from a
     configured hostname — the chart owns no DNS object and Garden's exposure
     materializer is the only writer of the real record. */}}
{{- define "gardenApp.surfaceName" -}}
{{- $tree := .Values.serviceTree -}}
{{- printf "%s.%s.%s.%s.%s.%s" $tree.module $tree.service $tree.platform .Values.instance $tree.landscape (trimAll "." .Values.zone) -}}
{{- end -}}

{{/* Service-tree labels only; every key is prefixed by labelPrefix. `instance`
     is deliberately NOT in this map. */}}
{{- define "gardenApp.serviceTreeLabels" -}}
{{- $prefix := include "gardenApp.labelPrefix" . -}}
{{- range $key, $value := .Values.serviceTree }}
{{ printf "%s/%s" $prefix $key }}: {{ $value | quote }}
{{- end }}
{{- end -}}

{{/* Instance metadata, kept SEPARATE from the LPSM labels: the instance key and
     the profile that selected this release. */}}
{{- define "gardenApp.instanceLabels" -}}
{{- $prefix := include "gardenApp.labelPrefix" . -}}
{{ printf "%s/instance" $prefix }}: {{ .Values.instance | quote }}
{{ printf "%s/profile" $prefix }}: {{ .Values.profile | quote }}
{{- end -}}

{{/* Selector labels: the immutable subset. LPSM plus the instance key, nothing
     version- or chart-derived. */}}
{{- define "gardenApp.selectorLabels" -}}
app.kubernetes.io/name: {{ .Values.serviceTree.service | quote }}
app.kubernetes.io/instance: {{ .Release.Name | quote }}
app.kubernetes.io/component: {{ .Values.serviceTree.module | quote }}
{{- end -}}

{{/* Labels for every owned object: LPSM + separate instance metadata. */}}
{{- define "gardenApp.labels" -}}
helm.sh/chart: {{ include "gardenApp.chart" . }}
{{ include "gardenApp.selectorLabels" . }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: {{ .Values.serviceTree.platform | quote }}
{{- include "gardenApp.serviceTreeLabels" . }}
{{ include "gardenApp.instanceLabels" . }}
{{- end -}}

{{/* Annotations for every owned object: the same identity plus the canonical
     dotted surface name, so an operator reading any object can resolve it. */}}
{{- define "gardenApp.annotations" -}}
{{ include "gardenApp.serviceTreeLabels" . | trim }}
{{ include "gardenApp.instanceLabels" . | trim }}
{{ include "gardenApp.labelPrefix" . }}/surface: {{ include "gardenApp.surfaceName" . | quote }}
{{- end -}}

{{/* Fully qualified image reference. A digest wins over a tag; one immutable
     image is SELECTED by each profile, never rebuilt per landscape. */}}
{{- define "gardenApp.image" -}}
{{- $image := .Values.image -}}
{{- $repository := required "image.repository is required" $image.repository -}}
{{- if $image.digest -}}
{{- printf "%s@%s" $repository $image.digest -}}
{{- else if $image.tag -}}
{{- printf "%s:%s" $repository $image.tag -}}
{{- else -}}
{{- fail "image.digest or image.tag is required: the workload runs one immutable standalone image" -}}
{{- end -}}
{{- end -}}

{{/* The resolved runtime landscape. Server-fed (R21); the browser never detects
     it. An empty override falls back to the LPSM landscape slot. */}}
{{- define "gardenApp.runtimeLandscape" -}}
{{- .Values.runtime.landscape | default .Values.serviceTree.landscape -}}
{{- end -}}

{{/* ServiceAccount name; empty means the conventional `<service>-<module>`. */}}
{{- define "gardenApp.serviceAccountName" -}}
{{- if .Values.serviceAccount.name -}}
{{- .Values.serviceAccount.name -}}
{{- else -}}
{{- include "gardenApp.resourceName" (dict "root" . "token" .Values.serviceTree.module) -}}
{{- end -}}
{{- end -}}
