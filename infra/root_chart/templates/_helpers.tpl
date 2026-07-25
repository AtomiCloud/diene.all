{{/* ### bun-consumer-helpers */}}
{{/* #### source: bun-consumer */}}

{{/* Stable chart identity. */}}
{{- define "bunconsumer.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/* The one and only service-tree label/annotation prefix (R16/B26). */}}
{{- define "bunconsumer.labelPrefix" -}}
{{- required "labelPrefix is required" .Values.labelPrefix | trimSuffix "/" -}}
{{- end -}}

{{/* Validate the LPSM projection before anything renders. */}}
{{- define "bunconsumer.validateServiceTree" -}}
{{- $serviceTree := required "serviceTree is required" .Values.serviceTree -}}
{{- $_ := required "serviceTree.platform is required" $serviceTree.platform -}}
{{- $service := required "serviceTree.service is required" $serviceTree.service -}}
{{- $_ = required "serviceTree.module is required" $serviceTree.module -}}
{{- $_ = required "serviceTree.layer is required" $serviceTree.layer -}}
{{- if not (regexMatch "^[a-z0-9]+$" $service) -}}
{{- fail (printf "serviceTree.service %q must be a dash-less lowercase token (fullname convention <service>-<token>, B30.4)" $service) -}}
{{- end -}}
{{- end -}}

{{/* Build an exactly-one-dash resource name from service + fused token (B30.4). */}}
{{- define "bunconsumer.resourceName" -}}
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

{{/* Service-tree labels only; every key is prefixed by labelPrefix. Landscape and
     cluster slots arrive through the independent overlay dimensions and project
     automatically. */}}
{{- define "bunconsumer.serviceTreeLabels" -}}
{{- $prefix := include "bunconsumer.labelPrefix" . -}}
{{- range $key, $value := .Values.serviceTree }}
{{ printf "%s/%s" $prefix $key }}: {{ $value | quote }}
{{- end }}
{{- end -}}

{{/* Immutable selector labels — never include chart version or service-tree slots
     that overlays may add, or a rollout would become a selector change. */}}
{{- define "bunconsumer.selectorLabels" -}}
app.kubernetes.io/name: {{ .Values.serviceTree.service | quote }}
app.kubernetes.io/instance: {{ .Release.Name | quote }}
app.kubernetes.io/component: {{ .Values.serviceTree.module | quote }}
{{- end -}}

{{/* Labels for one owned resource, with an explicit component. Callers that are
     not the worker workload (the db-init hook pair) pass their own component so
     the key is written exactly once. */}}
{{- define "bunconsumer.labelsFor" -}}
{{- $root := .root -}}
helm.sh/chart: {{ include "bunconsumer.chart" $root }}
app.kubernetes.io/name: {{ $root.Values.serviceTree.service | quote }}
app.kubernetes.io/instance: {{ $root.Release.Name | quote }}
app.kubernetes.io/component: {{ required "component is required" .component | quote }}
app.kubernetes.io/version: {{ $root.Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ $root.Release.Service }}
app.kubernetes.io/part-of: {{ $root.Values.serviceTree.platform | quote }}
{{- include "bunconsumer.serviceTreeLabels" $root }}
{{- end -}}

{{/* Labels for every owned resource of the worker module. */}}
{{- define "bunconsumer.labels" -}}
{{- include "bunconsumer.labelsFor" (dict "root" . "component" .Values.serviceTree.module) -}}
{{- end -}}

{{/* Service-tree annotations for every owned resource. */}}
{{- define "bunconsumer.annotations" -}}
{{ include "bunconsumer.serviceTreeLabels" . | trim }}
{{- end -}}

{{/* Pinned image reference. `tag` falls back to the chart appVersion, which CD
     pins to the one shared semver; `:latest` is never rendered. */}}
{{- define "bunconsumer.image" -}}
{{- $repository := required "image.repository is required" .Values.image.repository -}}
{{- $tag := .Values.image.tag | default .Chart.AppVersion -}}
{{- if or (not $tag) (eq (toString $tag) "latest") -}}
{{- fail "image tag must be a pinned version; `latest` is forbidden (M25)" -}}
{{- end -}}
{{- printf "%s:%s" $repository (toString $tag) -}}
{{- end -}}

{{/* The service-tree `app:` block projected as ATOMI_ env overrides (R14/R21).
     Config stays the source of truth; these are the deployment-context overrides.
     Only the keys the app config's `app:` block declares are projected — a cluster
     anchor added by an overlay is a label/annotation slot, not a config key. */}}
{{- define "bunconsumer.serviceTreeEnv" -}}
{{- $serviceTree := .Values.serviceTree -}}
{{- range $key := (list "platform" "service" "module" "layer" "landscape") }}
{{- $value := get $serviceTree $key }}
{{- if $value }}
- name: {{ printf "ATOMI_APP__%s" (upper $key) }}
  value: {{ $value | quote }}
{{- end }}
{{- end }}
- name: ATOMI_APP__VERSION
  value: {{ .Chart.AppVersion | quote }}
{{- end -}}

{{/* Env shared by the worker and db-init containers. */}}
{{- define "bunconsumer.commonEnv" -}}
{{- include "bunconsumer.serviceTreeEnv" . }}
- name: POD_NAME
  valueFrom:
    fieldRef:
      fieldPath: metadata.name
- name: POD_NAMESPACE
  valueFrom:
    fieldRef:
      fieldPath: metadata.namespace
{{- end -}}

{{/* envFrom sources shared by the worker and db-init containers. The service
     secret is optional so a bare install (no ESO) still schedules. */}}
{{- define "bunconsumer.envFrom" -}}
{{- if .Values.secret.enabled }}
- secretRef:
    name: {{ .Values.serviceTree.service | quote }}
    optional: true
{{- end }}
{{- end -}}

{{/* Build-phase config vendoring (B30.3). The app's config YAMLs live OUTSIDE the
     chart; the helm build step copies them into `files/config/` (gitignored, never
     committed). `.Files.Glob` returns an empty set when the copy has not run, so
     lint and template stay green with zero optional files present. */}}
{{- define "bunconsumer.configData" -}}
{{- $root := . -}}
{{- $pattern := printf "%s/*" (trimSuffix "/" $root.Values.config.path) -}}
{{- range $path, $_ := $root.Files.Glob $pattern }}
{{ base $path }}: |
{{ $root.Files.Get $path | indent 2 }}
{{- end }}
{{- end -}}

{{/* Volumes shared by the worker and db-init pods. readOnlyRootFilesystem is on,
     so the runtime needs a writable scratch dir. `configMapName` selects which
     config copy this pod mounts — the release-scoped one for the Deployment, the
     hook-scoped one for the pre-sync Job. */}}
{{- define "bunconsumer.volumes" -}}
{{- $root := .root -}}
- name: tmp
  emptyDir: {}
{{- if $root.Values.config.enabled }}
- name: config
  configMap:
    name: {{ .configMapName }}
{{- end }}
{{- end -}}

{{- define "bunconsumer.volumeMounts" -}}
{{- $root := .root -}}
- name: tmp
  mountPath: /tmp
{{- if $root.Values.config.enabled }}
- name: config
  mountPath: {{ $root.Values.config.mountPath }}
  readOnly: true
{{- end }}
{{- end -}}
