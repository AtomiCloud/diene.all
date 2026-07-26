{{/* ### go-consumer-helpers */}}
{{/* #### source: go-consumer */}}

{{/* Stable chart identity. */}}
{{- define "goconsumer.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/* The one and only service-tree label/annotation prefix (R16/B26). */}}
{{- define "goconsumer.labelPrefix" -}}
{{- required "labelPrefix is required" .Values.labelPrefix | trimSuffix "/" -}}
{{- end -}}

{{/* Validate the LPSM projection before anything renders. */}}
{{- define "goconsumer.validateServiceTree" -}}
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
{{- define "goconsumer.resourceName" -}}
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
{{- define "goconsumer.serviceTreeLabels" -}}
{{- $prefix := include "goconsumer.labelPrefix" . -}}
{{- range $key, $value := .Values.serviceTree }}
{{ printf "%s/%s" $prefix $key }}: {{ $value | quote }}
{{- end }}
{{- end -}}

{{/* Immutable selector labels — never include chart version or service-tree slots
     that overlays may add, or a rollout would become a selector change. */}}
{{- define "goconsumer.selectorLabels" -}}
app.kubernetes.io/name: {{ .Values.serviceTree.service | quote }}
app.kubernetes.io/instance: {{ .Release.Name | quote }}
app.kubernetes.io/component: {{ .Values.serviceTree.module | quote }}
{{- end -}}

{{/* Labels for one owned resource, with an explicit component. Callers that are
     not the worker workload (the db-init hook pair) pass their own component so
     the key is written exactly once. */}}
{{- define "goconsumer.labelsFor" -}}
{{- $root := .root -}}
helm.sh/chart: {{ include "goconsumer.chart" $root }}
app.kubernetes.io/name: {{ $root.Values.serviceTree.service | quote }}
app.kubernetes.io/instance: {{ $root.Release.Name | quote }}
app.kubernetes.io/component: {{ required "component is required" .component | quote }}
app.kubernetes.io/version: {{ $root.Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ $root.Release.Service }}
app.kubernetes.io/part-of: {{ $root.Values.serviceTree.platform | quote }}
{{- include "goconsumer.serviceTreeLabels" $root }}
{{- end -}}

{{/* Labels for every owned resource of the worker module. */}}
{{- define "goconsumer.labels" -}}
{{- include "goconsumer.labelsFor" (dict "root" . "component" .Values.serviceTree.module) -}}
{{- end -}}

{{/* Service-tree annotations for every owned resource. */}}
{{- define "goconsumer.annotations" -}}
{{ include "goconsumer.serviceTreeLabels" . | trim }}
{{- end -}}

{{/* Pinned image reference. `tag` falls back to the chart appVersion, which CD
     pins to the one shared semver; `:latest` is never rendered. */}}
{{- define "goconsumer.image" -}}
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
{{- define "goconsumer.serviceTreeEnv" -}}
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

{{/* Env shared by the worker and db-init containers. The heartbeat path is
     projected because `readOnlyRootFilesystem` is on: the config default may only
     be honoured if it resolves inside the writable scratch mount, so the chart —
     which owns the mount layout — is the only layer that can state it correctly. */}}
{{- define "goconsumer.commonEnv" -}}
{{- include "goconsumer.serviceTreeEnv" . }}
- name: ATOMI_HEALTH__HEARTBEATFILE
  value: {{ required "health.heartbeatFile is required" .Values.health.heartbeatFile | quote }}
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
{{- define "goconsumer.envFrom" -}}
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
{{- define "goconsumer.configData" -}}
{{- $root := . -}}
{{- $pattern := printf "%s/*" (trimSuffix "/" $root.Values.config.path) -}}
{{- range $path, $_ := $root.Files.Glob $pattern }}
{{ base $path }}: |
{{ $root.Files.Get $path | indent 2 }}
{{- end }}
{{- end -}}

{{/* Whether a config ConfigMap exists to render and mount at all. The image bakes
     `config/` in at the same path, so mounting an EMPTY ConfigMap would shadow
     those defaults with nothing. Mount only when the build-phase copy actually
     produced files; otherwise the image's own config stays visible. */}}
{{- define "goconsumer.hasConfig" -}}
{{- if .Values.config.enabled -}}
{{- include "goconsumer.configData" . | trim -}}
{{- end -}}
{{- end -}}

{{/* Volumes shared by the worker and db-init pods. readOnlyRootFilesystem is on,
     so the runtime needs a writable scratch dir — and it is where the worker
     heartbeat lives. `configMapName` selects which config copy this pod mounts —
     the release-scoped one for the Deployment, the hook-scoped one for the
     pre-sync Job. */}}
{{- define "goconsumer.volumes" -}}
{{- $root := .root -}}
- name: tmp
  emptyDir: {}
{{- if include "goconsumer.hasConfig" $root }}
- name: config
  configMap:
    name: {{ .configMapName }}
{{- end }}
{{- end -}}

{{- define "goconsumer.volumeMounts" -}}
{{- $root := .root -}}
- name: tmp
  mountPath: /tmp
{{- if include "goconsumer.hasConfig" $root }}
- name: config
  mountPath: {{ $root.Values.config.mountPath }}
  readOnly: true
{{- end }}
{{- end -}}
