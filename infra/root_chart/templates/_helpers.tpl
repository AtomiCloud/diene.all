{{/* ### dotnet-api-helpers */}}
{{/* #### source: dotnet-api */}}

{{/* Stable chart identity. */}}
{{- define "dotnetapi.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/* The one and only service-tree label/annotation prefix (R16/B26). */}}
{{- define "dotnetapi.labelPrefix" -}}
{{- required "labelPrefix is required" .Values.labelPrefix | trimSuffix "/" -}}
{{- end -}}

{{/* Validate the LPSM projection before anything renders. Every slot is a DNS-1123 label
     because all four are pasted into resource names, label values, and the error-portal type
     URI the application mints at runtime. */}}
{{- define "dotnetapi.validateServiceTree" -}}
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
{{- define "dotnetapi.resourceName" -}}
{{- $root := .root -}}
{{- $service := required "serviceTree.service is required" $root.Values.serviceTree.service | lower -}}
{{- $token := required "resource token is required" .token | lower -}}
{{- if not (regexMatch "^[a-z0-9]+$" $token) -}}
{{- fail (printf "token %q must be a dash-less lowercase token" .token) -}}
{{- end -}}
{{- printf "%s-%s" $service $token | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/* The service name folded into a legal environment-variable prefix: upper-cased with every
     non-alphanumeric run collapsed to `_`. `dotnet-api` -> `DOTNET_API`. Doing this in one
     helper is what stops `upper .Values.serviceTree.service` from silently emitting
     `DOTNET-API`, which is not a name any shell or container runtime will accept. */}}
{{- define "dotnetapi.envPrefix" -}}
{{- regexReplaceAll "[^A-Z0-9]+" (upper .Values.serviceTree.service) "_" | trimSuffix "_" -}}
{{- end -}}

{{/* Service-tree labels only; every key is prefixed by labelPrefix. */}}
{{- define "dotnetapi.serviceTreeLabels" -}}
{{- $prefix := include "dotnetapi.labelPrefix" . -}}
{{- range $key, $value := .Values.serviceTree }}
{{ printf "%s/%s" $prefix $key }}: {{ $value | quote }}
{{- end }}
{{- end -}}

{{/* Immutable selector labels — never the chart version and never a service-tree slot an
     overlay may add, or a rollout would become a selector change, which is an immutable-field
     conflict on an existing Deployment. */}}
{{- define "dotnetapi.selectorLabels" -}}
app.kubernetes.io/name: {{ .Values.serviceTree.service | quote }}
app.kubernetes.io/instance: {{ .Release.Name | quote }}
app.kubernetes.io/component: {{ .Values.serviceTree.module | quote }}
{{- end -}}

{{/* Labels for one owned resource, with an explicit component. The db-init hook pair passes
     its own component so the key is written exactly once. */}}
{{- define "dotnetapi.labelsFor" -}}
{{- $root := .root -}}
helm.sh/chart: {{ include "dotnetapi.chart" $root }}
app.kubernetes.io/name: {{ $root.Values.serviceTree.service | quote }}
app.kubernetes.io/instance: {{ $root.Release.Name | quote }}
app.kubernetes.io/component: {{ required "component is required" .component | quote }}
app.kubernetes.io/version: {{ $root.Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ $root.Release.Service }}
app.kubernetes.io/part-of: {{ $root.Values.serviceTree.platform | quote }}
{{- include "dotnetapi.serviceTreeLabels" $root }}
{{- end -}}

{{/* Labels for every owned resource of the serving module. */}}
{{- define "dotnetapi.labels" -}}
{{- include "dotnetapi.labelsFor" (dict "root" . "component" .Values.serviceTree.module) -}}
{{- end -}}

{{/* Service-tree annotations for every owned resource. */}}
{{- define "dotnetapi.annotations" -}}
{{ include "dotnetapi.serviceTreeLabels" . | trim }}
{{- end -}}

{{/* Pinned image reference. `tag` falls back to the chart appVersion, which the
     `chart-versions` gate holds equal to the repository VERSION; `:latest` is never rendered
     (M25). */}}
{{- define "dotnetapi.image" -}}
{{- $repository := required "image.repository is required" .Values.image.repository -}}
{{- $tag := .Values.image.tag | default .Chart.AppVersion -}}
{{- if or (not $tag) (eq (toString $tag) "latest") -}}
{{- fail "image tag must be a pinned version; `latest` is forbidden (M25)" -}}
{{- end -}}
{{- printf "%s:%s" $repository (toString $tag) -}}
{{- end -}}

{{/* Graceful-shutdown alignment. ASP.NET Core's own drain budget and the kubelet's grace
     period are ONE decision expressed as two numbers, so the chart refuses to render a
     combination where the kubelet would SIGKILL a host that is still draining in-flight
     requests. */}}
{{- define "dotnetapi.validateShutdown" -}}
{{- $timeout := required "shutdown.timeoutSeconds is required" .Values.shutdown.timeoutSeconds | int -}}
{{- $grace := required "shutdown.terminationGracePeriodSeconds is required" .Values.shutdown.terminationGracePeriodSeconds | int -}}
{{- if le $grace $timeout -}}
{{- fail (printf "shutdown.terminationGracePeriodSeconds (%d) must exceed shutdown.timeoutSeconds (%d): the kubelet would SIGKILL the host while ASP.NET Core is still draining" $grace $timeout) -}}
{{- end -}}
{{- end -}}

{{/* The service-tree `app:` block projected as ATOMI_ env overrides (R14/R21). The YAML in the
     ConfigMap stays the source of truth for everything else; these are the deployment-context
     overrides, and they exist so the Kubernetes labels and the OTEL resource attributes are
     the same strings. `LANDSCAPE` is separate and load-bearing: the config loader reads it to
     pick `Config/settings.<landscape>.yaml`, and nothing else supplies it in-cluster. */}}
{{- define "dotnetapi.serviceTreeEnv" -}}
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
- name: LANDSCAPE
  value: {{ .Values.serviceTree.landscape | quote }}
{{- end -}}

{{/* Env shared by the app and db-init containers. */}}
{{- define "dotnetapi.commonEnv" -}}
{{- include "dotnetapi.serviceTreeEnv" . }}
- name: DOTNET_CLI_TELEMETRY_OPTOUT
  value: '1'
- name: POD_NAME
  valueFrom:
    fieldRef:
      fieldPath: metadata.name
- name: POD_NAMESPACE
  valueFrom:
    fieldRef:
      fieldPath: metadata.namespace
{{- end -}}

{{/* Env only the serving container needs. The port is stated ONCE, in `app.port`: the
     containerPort, the Service targetPort, and the address Kestrel binds all derive from it,
     so a changed port cannot leave the probe pointing at a closed socket. */}}
{{- define "dotnetapi.serverEnv" -}}
- name: ASPNETCORE_URLS
  value: {{ printf "http://+:%d" (int .Values.app.port) | quote }}
- name: ASPNETCORE_SHUTDOWNTIMEOUTSECONDS
  value: {{ .Values.shutdown.timeoutSeconds | quote }}
{{- end -}}

{{/* envFrom sources shared by both containers. The service secret is `optional` because on a
     FIRST install the pre-sync Job runs before the ExternalSecret has materialized its target
     — a hard reference would leave db-init stuck in CreateContainerConfigError forever. */}}
{{- define "dotnetapi.envFrom" -}}
{{- if .Values.secret.enabled }}
- secretRef:
    name: {{ .Values.serviceTree.service | quote }}
    optional: true
{{- end }}
{{- end -}}

{{/* Build-phase config vendoring. The app's config YAMLs live OUTSIDE the chart in
     `App/Config/`; the helm build step (`pls helm:vendor`) copies them into `files/config/`,
     which is gitignored and never committed. `.Files.Glob` returns an empty set when the copy
     has not run, so lint and template stay green with zero optional files present. */}}
{{- define "dotnetapi.configData" -}}
{{- $root := . -}}
{{- $pattern := printf "%s/*.yaml" (trimSuffix "/" $root.Values.config.path) -}}
{{- range $path, $_ := $root.Files.Glob $pattern }}
{{ base $path }}: |
{{ $root.Files.Get $path | indent 2 }}
{{- end }}
{{- end -}}

{{/* Whether there is a config ConfigMap to render and mount at all. The image bakes `Config/`
     in at this same path, so mounting an EMPTY ConfigMap would shadow those defaults with
     nothing. Rendering nothing when the copy has not run is the CORRECT outcome, not a
     degraded one: the image's own config stays visible. */}}
{{- define "dotnetapi.hasConfig" -}}
{{- if .Values.config.enabled -}}
{{- include "dotnetapi.configData" . | trim -}}
{{- end -}}
{{- end -}}

{{/* Volumes shared by both pods. `readOnlyRootFilesystem` is on, so the .NET runtime needs a
     writable scratch dir for its temp files. `configMapName` selects which config copy this
     pod mounts — the release-scoped one for the Deployment, the hook-scoped one for the
     pre-sync Job. */}}
{{- define "dotnetapi.volumes" -}}
{{- $root := .root -}}
- name: tmp
  emptyDir: {}
{{- if include "dotnetapi.hasConfig" $root }}
- name: config
  configMap:
    name: {{ .configMapName }}
{{- end }}
{{- end -}}

{{- define "dotnetapi.volumeMounts" -}}
{{- $root := .root -}}
- name: tmp
  mountPath: /tmp
{{- if include "dotnetapi.hasConfig" $root }}
- name: config
  mountPath: {{ $root.Values.config.mountPath }}
  readOnly: true
{{- end }}
{{- end -}}
