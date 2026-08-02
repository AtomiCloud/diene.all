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

{{/*
  Preview manifest boundary (concepts/environments.md §3a).
  The manifest reaching this chart is already fully resolved by the authorized
  assembler: every pin is a released version, a full commit, or an operator
  rollout. A branch pin is resolved to its commit AT MINT and the preview never
  follows the branch afterwards, so an unresolved pin refuses here rather than
  being resolved locally. Emits nothing; it only refuses.
*/}}
{{- define "diene-helm-wrapper.previewManifest" -}}
{{- $manifest := .Values.instance | default dict | dig "preview" dict | default dict | dig "manifest" dict -}}
{{- $version := "^v?[0-9]+\\.[0-9]+\\.[0-9]+([.+-][0-9A-Za-z.+-]*)?$" -}}
{{- $commit := "^[0-9a-f]{40}$" -}}
{{- if not (index $manifest "defaultChannelRef") -}}
{{- fail "PreviewIdentityUnavailable: the resolved preview manifest carries no default-channel reference" -}}
{{- end -}}
{{- $pins := (index $manifest "pins") | default dict -}}
{{- if not $pins -}}
{{- fail "PreviewIdentityUnavailable: the resolved preview manifest pin map is empty" -}}
{{- end -}}
{{- range $key, $pin := $pins -}}
{{- if not (regexMatch "^[a-z0-9]([a-z0-9-]*[a-z0-9])?\\.[a-z0-9]([a-z0-9-]*[a-z0-9])?$" $key) -}}
{{- fail (printf "PreviewIdentityUnavailable: pin key %q must be <platform>.<service> DNS-1123 labels with no module segment" $key) -}}
{{- end -}}
{{- if kindIs "map" $pin -}}
{{- if ne (keys $pin | sortAlpha | join ",") "kind,version" -}}
{{- fail (printf "PreviewIdentityUnavailable: operator pin %q must carry exactly kind and version, got %q" $key (keys $pin | sortAlpha | join ",")) -}}
{{- end -}}
{{- if ne (index $pin "kind" | toString) "operator" -}}
{{- fail (printf "PreviewIdentityUnavailable: pin %q has kind %q; only an operator rollout uses the object form" $key (index $pin "kind")) -}}
{{- end -}}
{{- if not (regexMatch $version (index $pin "version" | toString)) -}}
{{- fail (printf "PreviewIdentityUnavailable: operator pin %q version %q is not a released version" $key (index $pin "version")) -}}
{{- end -}}
{{- else if kindIs "string" $pin -}}
{{- if not (or (regexMatch $commit $pin) (regexMatch $version $pin)) -}}
{{- fail (printf "PreviewIdentityUnavailable: pin %q for %q is neither a released version nor a full commit; a branch pin must be resolved to its commit at mint" $pin $key) -}}
{{- end -}}
{{- else -}}
{{- fail (printf "PreviewIdentityUnavailable: pin %q must be a scalar version, a scalar commit, or an operator object" $key) -}}
{{- end -}}
{{- end -}}
{{- range $key, $resolution := ((index $manifest "branchResolutions") | default dict) -}}
{{- $branch := (index $resolution "branch") | default "" -}}
{{- $resolved := (index $resolution "commit") | default "" -}}
{{- if not $branch -}}
{{- fail (printf "PreviewIdentityUnavailable: branch resolution for %q records no branch" $key) -}}
{{- end -}}
{{- if not (regexMatch $commit $resolved) -}}
{{- fail (printf "PreviewIdentityUnavailable: branch %q for %q resolved to %q, not a full commit" $branch $key $resolved) -}}
{{- end -}}
{{- if not (hasKey $pins $key) -}}
{{- fail (printf "PreviewIdentityUnavailable: branch resolution %q has no matching manifest pin" $key) -}}
{{- end -}}
{{- if ne (index $pins $key | toString) $resolved -}}
{{- fail (printf "PreviewIdentityUnavailable: branch %q resolved to %q but the manifest pins %q; a preview never follows its branch past mint" $branch $resolved (index $pins $key)) -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
  Preview identity boundary (concepts/environments.md §3a, R-P9).
  The chart accepts ONLY the authorized assembler's typed CanonicalPreviewInstance
  bound to its receipt. It never mints, canonicalizes, lowercases, truncates,
  hashes, or suffixes a petname, and never emits the internal leaseKey or full
  digest into a rendered object. Returns the recorded petname or refuses.
*/}}
{{- define "diene-helm-wrapper.previewPetname" -}}
{{- $preview := .Values.instance | default dict | dig "preview" dict -}}
{{- $canonical := (index $preview "canonical") | default dict -}}
{{- $receipt := (index $preview "receipt") | default dict -}}
{{- range $field := list "previewPetname" "fullLeaseDigest" "leaseKey" "schema" "wordList" "forkSource" "requester" "mintedAt" "signature" -}}
{{- if not (index $receipt $field) -}}
{{- fail (printf "PreviewIdentityUnavailable: the assembler receipt is missing %q" $field) -}}
{{- end -}}
{{- end -}}
{{- $petname := index $receipt "previewPetname" -}}
{{- $digest := index $receipt "fullLeaseDigest" -}}
{{- $leaseKey := index $receipt "leaseKey" -}}
{{- if not (regexMatch "^diene\\.preview-manifest/v[0-9]+$" (index $receipt "schema")) -}}
{{- fail (printf "PreviewIdentityUnavailable: manifest schema %q is not a versioned diene.preview-manifest schema" (index $receipt "schema")) -}}
{{- end -}}
{{- if not (regexMatch "^diene\\.preview-wordlist/v[0-9]+$" (index $receipt "wordList")) -}}
{{- fail (printf "PreviewIdentityUnavailable: petname word list %q is not a versioned diene.preview-wordlist" (index $receipt "wordList")) -}}
{{- end -}}
{{- if not (has (index $receipt "forkSource") (list "staging" "production")) -}}
{{- fail (printf "PreviewIdentityUnavailable: forkSource %q is neither staging nor production" (index $receipt "forkSource")) -}}
{{- end -}}
{{- if not (regexMatch "^[0-9a-f]{64}$" $digest) -}}
{{- fail (printf "PreviewIdentityUnavailable: fullLeaseDigest %q is not a 64-character lowercase hex SHA-256 digest" $digest) -}}
{{- end -}}
{{- if not (regexMatch "^p[0-9a-v]{26}$" $leaseKey) -}}
{{- fail (printf "PreviewIdentityUnavailable: leaseKey %q is not the internal base32hex lease key" $leaseKey) -}}
{{- end -}}
{{- if not (regexMatch "^[a-z]+-[a-z]+-[a-z]+(-[0-9a-v]{3})?$" $petname) -}}
{{- fail (printf "PreviewIdentityUnavailable: %q is not a versioned NOUN-VERB-NOUN petname" $petname) -}}
{{- end -}}
{{- if gt (len $petname) 63 -}}
{{- fail (printf "PreviewIdentityUnavailable: petname %q is longer than one DNS-1123 label" $petname) -}}
{{- end -}}
{{- if ne ((index $canonical "previewPetname") | toString) $petname -}}
{{- fail (printf "PreviewIdentityMismatch: canonical instance %q is not the petname %q recorded at mint" (index $canonical "previewPetname") $petname) -}}
{{- end -}}
{{- if ne ((index $canonical "fullLeaseDigest") | toString) $digest -}}
{{- fail (printf "PreviewIdentityMismatch: canonical full digest %q does not equal the receipt digest %q" (index $canonical "fullLeaseDigest") $digest) -}}
{{- end -}}
{{- $liveDigest := ((index $receipt "collision") | default dict | dig "liveFullLeaseDigest" "" ) -}}
{{- if $liveDigest -}}
{{- if not (regexMatch "^[0-9a-f]{64}$" $liveDigest) -}}
{{- fail (printf "PreviewIdentityUnavailable: recorded live-collision digest %q is not a 64-character lowercase hex SHA-256 digest" $liveDigest) -}}
{{- end -}}
{{- if eq $liveDigest $digest -}}
{{- fail "PreviewIdentityMismatch: a live allocation carrying the same full digest is an idempotent join, never a petname collision" -}}
{{- end -}}
{{- end -}}
{{- $parts := splitList "-" $petname -}}
{{- $suffix := "" -}}
{{- if eq (len $parts) 4 -}}
{{- $suffix = index $parts 3 -}}
{{- end -}}
{{- if $suffix -}}
{{- if not $liveDigest -}}
{{- fail (printf "PreviewIdentityMismatch: petname %q carries a collision suffix with no recorded live base-petname collision" $petname) -}}
{{- end -}}
{{- if ne $suffix (substr 1 4 $leaseKey) -}}
{{- fail (printf "PreviewIdentityMismatch: collision suffix %q is not the first three base32hex digest characters %q" $suffix (substr 1 4 $leaseKey)) -}}
{{- end -}}
{{- else if $liveDigest -}}
{{- fail (printf "PreviewIdentityMismatch: a live base-petname collision is recorded but %q carries no collision suffix" $petname) -}}
{{- end -}}
{{- include "diene-helm-wrapper.previewManifest" . -}}
{{- $petname -}}
{{- end -}}

{{/*
  The single physical instance segment. A preview takes the receipt-bound petname
  byte-for-byte; every other landscape supplies an already-DNS-1123 segment that
  this chart records verbatim.
*/}}
{{- define "diene-helm-wrapper.instanceSegment" -}}
{{- $instance := .Values.instance | default dict -}}
{{- if (index $instance "preview" | default dict | dig "enabled" false) -}}
{{- include "diene-helm-wrapper.previewPetname" . -}}
{{- else -}}
{{- $original := (index $instance "original") | default "" -}}
{{- if $original -}}
{{- if not (regexMatch "^[a-z0-9]([a-z0-9-]*[a-z0-9])?$" $original) -}}
{{- fail (printf "instance.original %q is not already a DNS-1123 label; this chart records a physical instance id verbatim and never normalizes it" $original) -}}
{{- end -}}
{{- if gt (len $original) 63 -}}
{{- fail (printf "instance.original %q is longer than one DNS-1123 label; shorten it at the authorized minter, never here" $original) -}}
{{- end -}}
{{- $original -}}
{{- end -}}
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
{{- $expected := include "diene-helm-wrapper.resourceName" (dict "root" . "token" .Values.serviceTree.module) -}}
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

{{/*
  Service-tree plus recorded instance metadata annotations. Original and label are
  the same bytes: the chart records what the authorized minter assigned and derives
  neither from the other. The internal leaseKey and full digest are never stamped.
*/}}
{{- define "diene-helm-wrapper.annotations" -}}
{{- $prefix := include "diene-helm-wrapper.labelPrefix" . -}}
{{- range $key, $value := .Values.serviceTree }}
{{ printf "%s/%s" $prefix $key }}: {{ $value | quote }}
{{- end }}
{{- with include "diene-helm-wrapper.instanceSegment" . }}
{{ printf "%s/instance-original" $prefix }}: {{ . | quote }}
{{ printf "%s/instance-label" $prefix }}: {{ . | quote }}
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

{{/*
  The castform preview coordinate. It reuses the ordinary instance projection with
  two slots the caller cannot choose: the platform comes from the release namespace
  and the landscape is the one ruled preview landscape. The instance slot is the
  receipt-bound petname byte-for-byte; the leaseKey and digest never reach DNS.
*/}}
{{- define "diene-helm-wrapper.previewHostname" -}}
{{- $root := .root -}}
{{- include "diene-helm-wrapper.hostname" (dict "root" $root "module" .module "service" .service "landscape" "castform" "instance" (include "diene-helm-wrapper.previewPetname" $root) "zone" .zone) -}}
{{- end -}}

{{/* Parse a hostname back into the unchanged four-slot LPSM coordinate plus instance. */}}
{{- define "diene-helm-wrapper.parseHostname" -}}
{{- $hostname := required "hostname is required" .hostname -}}
{{- $zone := required "zone is required" .zone | trimPrefix "." -}}
{{- range $label := splitList "." (printf "%s.%s" $hostname $zone) -}}
{{- if or (gt (len $label) 63) (not (regexMatch "^[a-z0-9]([a-z0-9-]*[a-z0-9])?$" $label)) -}}
{{- fail (printf "hostname label %q must be a lowercase DNS-1123 label" $label) -}}
{{- end -}}
{{- end -}}
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
