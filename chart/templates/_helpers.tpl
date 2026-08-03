{{/* Stable chart identity. */}}
{{- define "diene-helm-wrapper.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
  One DNS-1123 subdomain, judged the way Kubernetes judges a label-key prefix:
  at most 253 bytes, dot-separated lowercase alphanumeric labels with internal
  dashes only. Nothing here lowercases, trims, or truncates a byte to make an
  unusable prefix fit — an invalid prefix is refused at the boundary, because a
  prefix that cannot be a key would otherwise render an object the API server
  rejects long after the chart claimed success.
*/}}
{{- define "diene-helm-wrapper.assertLabelPrefix" -}}
{{- $prefix := . | toString -}}
{{- if eq $prefix "" -}}
{{- fail "LabelPrefixInvalid: the label prefix is empty; it must be one DNS-1123 subdomain" -}}
{{- end -}}
{{- if gt (len $prefix) 253 -}}
{{- fail (printf "LabelPrefixInvalid: label prefix %q is %d bytes; a label-key prefix is at most 253 bytes and this chart never truncates one" $prefix (len $prefix)) -}}
{{- end -}}
{{- range $index, $label := splitList "." $prefix -}}
{{- if eq $label "" -}}
{{- fail (printf "LabelPrefixInvalid: segment %d of label prefix %q is empty; every dot-separated segment is one DNS-1123 label" (add1 $index) $prefix) -}}
{{- end -}}
{{- if gt (len $label) 63 -}}
{{- fail (printf "LabelPrefixInvalid: segment %d of label prefix %q is %d bytes; a DNS-1123 label is at most 63 bytes" (add1 $index) $prefix (len $label)) -}}
{{- end -}}
{{- if not (regexMatch "^[a-z0-9]([a-z0-9-]*[a-z0-9])?$" $label) -}}
{{- fail (printf "LabelPrefixInvalid: segment %q of label prefix %q must start and end with a lowercase alphanumeric byte and hold only lowercase alphanumerics and internal dashes" $label $prefix) -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
  The one and only service-tree label/annotation prefix. It lives under `global`
  because Helm propagates that table verbatim into every pinned dependency, so
  the single wrapper decision is readable from an upstream template context too;
  a chart-local value would stop at the wrapper's own objects.
*/}}
{{- define "diene-helm-wrapper.labelPrefix" -}}
{{- $prefix := required "global.labelPrefix is required" ((.Values.global | default dict).labelPrefix) | toString | trimSuffix "/" -}}
{{- include "diene-helm-wrapper.assertLabelPrefix" $prefix -}}
{{- $prefix -}}
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
{{- $manifest := (.Values.global | default dict).instance | default dict | dig "preview" dict | default dict | dig "manifest" dict -}}
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
{{- $preview := (.Values.global | default dict).instance | default dict | dig "preview" dict -}}
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
  Physical instance identity boundary.

  The pair arrives ALREADY MINTED. The authorized minter owns the deterministic
  normalization, the stable hash-shortening that produces a label for an id longer
  than one DNS label, and the collision audit across live allocations. This chart
  owns exactly one thing: it judges the boundary shape of both halves and records
  them, so it never lowercases, truncates, hashes, normalizes, or improvises one
  half from the other.

  `original` is the unchanged repository-qualified id and is deliberately NOT a
  DNS label — refusing a long or repository-qualified id was the defect this
  replaces, because a shortening the chart cannot record is a shortening nobody
  can reverse or audit. `label` is the minter's DNS-1123 label and is the only
  half that ever becomes a hostname segment.

  The two are recorded together or not at all: an original alone would need a
  label minted here, and a label alone would record a shortening of nothing.

  The pair is read from `global.instance` rather than a chart-local table for the
  same reason `global.labelPrefix` lives there: Helm copies `global` verbatim into
  every pinned dependency, so ONE resolved identity is reachable from an upstream
  template context. A chart-local table stopped at the wrapper's own objects and
  forced the dependency's annotations to hard-code a second pair, which is how one
  release came to record two different physical instances under preview.
*/}}
{{- define "diene-helm-wrapper.assertInstancePair" -}}
{{- $instance := (.Values.global | default dict).instance | default dict -}}
{{- $original := (index $instance "original") | default "" | toString -}}
{{- $label := (index $instance "label") | default "" | toString -}}
{{- if and $original $label -}}
{{- if gt (len $original) 253 -}}
{{- fail (printf "InstanceOriginalInvalid: global.instance.original is %d bytes; a repository-qualified physical id is at most 253 bytes and this chart never shortens one" (len $original)) -}}
{{- end -}}
{{- if not (regexMatch "^[A-Za-z0-9]([A-Za-z0-9._:/-]*[A-Za-z0-9])?$" $original) -}}
{{- fail (printf "InstanceOriginalInvalid: global.instance.original %q must start and end with an alphanumeric byte and hold only alphanumerics, dots, underscores, colons, slashes, and dashes; a physical id carries no whitespace or control bytes" $original) -}}
{{- end -}}
{{- include "diene-helm-wrapper.dnsLabel" (dict "slot" "global.instance.label" "label" $label) -}}
{{- else if $original -}}
{{- fail (printf "InstancePairIncomplete: global.instance.original %q carries no global.instance.label; the authorized minter assigns that label and this chart never derives one" $original) -}}
{{- else if $label -}}
{{- fail (printf "InstancePairIncomplete: global.instance.label %q carries no global.instance.original; a shortened label is recorded only beside the id it shortens, or the shortening is unauditable" $label) -}}
{{- end -}}
{{- end -}}

{{/*
  The recorded original half. A preview records the receipt-bound petname for both
  halves, because an assembler-minted petname IS its own unshortened id.
*/}}
{{- define "diene-helm-wrapper.instanceOriginal" -}}
{{- $instance := (.Values.global | default dict).instance | default dict -}}
{{- if (index $instance "preview" | default dict | dig "enabled" false) -}}
{{- include "diene-helm-wrapper.previewPetname" . -}}
{{- else -}}
{{- include "diene-helm-wrapper.assertInstancePair" . -}}
{{- (index $instance "original") | default "" | toString -}}
{{- end -}}
{{- end -}}

{{/*
  The single physical instance hostname segment: the minter's DNS-1123 label, or
  the receipt-bound petname under preview. Never the original.
*/}}
{{- define "diene-helm-wrapper.instanceSegment" -}}
{{- $instance := (.Values.global | default dict).instance | default dict -}}
{{- if (index $instance "preview" | default dict | dig "enabled" false) -}}
{{- include "diene-helm-wrapper.previewPetname" . -}}
{{- else -}}
{{- include "diene-helm-wrapper.assertInstancePair" . -}}
{{- (index $instance "label") | default "" | toString -}}
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
  A hook object's own labels. A lifecycle hook is NOT the primary workload, so it
  must never be born wearing the primary workload's selector identity.

  Every primary Service selector and the Deployment's own `matchLabels` are
  exactly `selectorLabels`, so a hook pod stamped with the full
  `diene-helm-wrapper.labels` set carries a strict SUPERSET of all of them and is
  eligible for their EndpointSlices the whole time the hook runs. Nothing routed
  to it only because both Services name `targetPort: http` and the migration
  container declares no port — an accident of this sample, not a property of the
  shape every `charts/*` node inherits. The first hook container that declares an
  `http` port, or the first Service that switches to a numeric target, would put a
  migration pod behind the gateway LoadBalancer.

  So a hook keeps everything that makes it a service-tree object — the full
  projection under the prefix in force, chart, version, managed-by — and swaps
  exactly the workload identity: `app.kubernetes.io/name` becomes the hook's own
  `<service>-<token>` resource name and `app.kubernetes.io/component` records
  which hook it is. `instance` stays the release, as it is on every object.
*/}}
{{- define "diene-helm-wrapper.hookLabels" -}}
{{- $root := .root -}}
{{- $token := required "hook token is required" .token -}}
{{- $prefix := include "diene-helm-wrapper.labelPrefix" $root -}}
{{- include "diene-helm-wrapper.dnsLabel" (dict "slot" (printf "hook component for token %q" $token) "label" $token) -}}
helm.sh/chart: {{ include "diene-helm-wrapper.chart" $root }}
app.kubernetes.io/name: {{ include "diene-helm-wrapper.resourceName" (dict "root" $root "token" $token) }}
app.kubernetes.io/instance: {{ $root.Release.Name }}
app.kubernetes.io/component: {{ $token }}
{{- range $key, $value := $root.Values.serviceTree }}
{{ printf "%s/%s" $prefix $key }}: {{ $value | quote }}
{{- end }}
app.kubernetes.io/version: {{ $root.Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ $root.Release.Service }}
{{- end -}}

{{/*
  Service-tree plus recorded instance metadata annotations. Original and label are
  recorded as the DISTINCT bytes the authorized minter assigned, which is what makes
  a hash-shortened label reversible and collision-auditable from the object itself.
  The chart derives neither from the other, and the internal preview leaseKey and
  full digest are never stamped. Under preview both halves are the petname.
*/}}
{{- define "diene-helm-wrapper.annotations" -}}
{{- $prefix := include "diene-helm-wrapper.labelPrefix" . -}}
{{- $original := include "diene-helm-wrapper.instanceOriginal" . -}}
{{- $label := include "diene-helm-wrapper.instanceSegment" . -}}
{{- range $key, $value := .Values.serviceTree }}
{{ printf "%s/%s" $prefix $key }}: {{ $value | quote }}
{{- end }}
{{- if $label }}
{{ printf "%s/instance-original" $prefix }}: {{ $original | quote }}
{{ printf "%s/instance-label" $prefix }}: {{ $label | quote }}
{{- end }}
{{- end -}}

{{/*
  One rendered metadata key, judged as a Kubernetes qualified name. The upstream
  maps below are the only place a key is computed rather than written, so a key
  the API server would reject is refused here instead of reaching a manifest.
*/}}
{{- define "diene-helm-wrapper.assertMetadataKey" -}}
{{- $slot := .slot -}}
{{- $key := .key | toString -}}
{{- $parts := splitList "/" $key -}}
{{- if gt (len $parts) 2 -}}
{{- fail (printf "UpstreamMetadataKeyInvalid: rendered %s key %q carries more than one %q separator" $slot $key "/") -}}
{{- end -}}
{{- if eq (len $parts) 2 -}}
{{- include "diene-helm-wrapper.assertLabelPrefix" (first $parts) -}}
{{- end -}}
{{- $name := last $parts -}}
{{- if eq $name "" -}}
{{- fail (printf "UpstreamMetadataKeyInvalid: rendered %s key %q has an empty name segment" $slot $key) -}}
{{- end -}}
{{- if gt (len $name) 63 -}}
{{- fail (printf "UpstreamMetadataKeyInvalid: rendered %s key %q has a %d-byte name segment; a qualified name is at most 63 bytes" $slot $key (len $name)) -}}
{{- end -}}
{{- if not (regexMatch "^[A-Za-z0-9]([A-Za-z0-9._-]*[A-Za-z0-9])?$" $name) -}}
{{- fail (printf "UpstreamMetadataKeyInvalid: rendered %s key %q has a name segment that is not a Kubernetes qualified name" $slot $key) -}}
{{- end -}}
{{- end -}}

{{/*
  PINNED UPSTREAM INTERFACE — app-template 5.0.1 / bjw-s.common 5.0.1.

  Upstream's own `globalLabels`/`globalAnnotations` bind `$name := $k` and only
  `tpl` the VALUE, so a map KEY reaches every rendered upstream object verbatim.
  That is why a `global.labelPrefix` override used to move every wrapper-owned
  key while the upstream Deployment and Service kept the old prefix.

  Helm's template namespace is global and, because `sortTemplates` parses deeper
  paths first, the wrapper's shallow `templates/_helpers.tpl` is parsed after the
  dependency's `charts/upstream/charts/common/templates/lib/metadata/*.tpl`. A
  same-named definition here therefore REPLACES the upstream one for the whole
  render, including when the wrapper is rendered from a packaged archive. These
  two definitions reproduce the upstream emission byte-for-byte — one leading
  newline per entry, the value `tpl`-rendered against the dependency context, no
  trailing newline — and deviate in exactly TWO deliberate ways:

  1. The key is `tpl`-rendered too, so `global.labelPrefix` reaches an upstream
     key exactly as it reaches a wrapper-owned one.
  2. An entry whose rendered value is EMPTY is omitted rather than emitted with
     an empty value. A values map always carries its keys, so upstream's
     emission cannot express "this object records nothing"; the wrapper's own
     `annotations` helper can, and does, for the recorded instance pair. Both
     halves empty is a schema-valid configuration meaning no minted physical
     instance, so without this the same release would record two different
     things: thirteen wrapper-owned objects with neither instance key and the
     dependency's two wearing both keys with empty values — false-positiving
     anything that reads presence of `<prefix>/instance-label` as "this object
     belongs to a physical instance". Metadata-key validation still runs on
     every key that IS emitted; only the empty-valued entry is skipped, and no
     projection slot or reloader annotation is ever empty, so none is dropped.

  `scripts/validate/helm-wrapper.sh labels` re-checks that pinned interface
  against the vendored archive before it asserts a projection, so a dependency
  bump that renames these templates or starts templating its own keys is
  reported rather than silently dropping every upstream service-tree key.
*/}}
{{- define "bjw-s.common.lib.metadata.globalLabels" -}}
{{- include "diene-helm-wrapper.upstreamGlobalMetadata" (dict "root" . "slot" "label" "entries" ((.Values.global | default dict).labels | default dict)) -}}
{{- end -}}

{{- define "bjw-s.common.lib.metadata.globalAnnotations" -}}
{{- include "diene-helm-wrapper.upstreamGlobalMetadata" (dict "root" . "slot" "annotation" "entries" ((.Values.global | default dict).annotations | default dict)) -}}
{{- end -}}

{{- define "diene-helm-wrapper.upstreamGlobalMetadata" -}}
{{- $root := .root -}}
{{- $slot := .slot -}}
{{- range $key, $value := .entries }}
{{- $renderedKey := tpl $key $root }}
{{- $renderedValue := tpl $value $root }}
{{- if $renderedValue }}
{{- include "diene-helm-wrapper.assertMetadataKey" (dict "slot" $slot "key" $renderedKey) }}
{{ $renderedKey }}: {{ $renderedValue | quote }}
{{- end }}
{{- end }}
{{- end -}}

{{/* Reloader is opt-in at the controller and default-on in this wrapper. */}}
{{- define "diene-helm-wrapper.reloaderAnnotations" -}}
{{- if .enabled }}
reloader.stakater.com/auto: 'true'
{{- end }}
{{- end -}}

{{/*
  One DNS-1123 label, judged on the bytes it was handed. The inverse parser below
  has always demanded start/end alphanumerics and a 63-byte bound, so the forward
  derivation demands exactly the same: anything looser mints a coordinate the
  chart cannot read back. Every refusal names its slot AND its rule, and nothing
  here lowercases, trims, truncates, or pads a byte to make an invalid label fit —
  an unusable label is refused at the boundary, never repaired past it.
*/}}
{{- define "diene-helm-wrapper.dnsLabel" -}}
{{- $slot := .slot -}}
{{- $label := .label | toString -}}
{{- if eq $label "" -}}
{{- fail (printf "HostnameLabelInvalid: %s is empty; every hostname slot must carry exactly one DNS-1123 label" $slot) -}}
{{- end -}}
{{- if gt (len $label) 63 -}}
{{- fail (printf "HostnameLabelInvalid: %s %q is %d bytes; a DNS-1123 label is at most 63 bytes and this chart never truncates one" $slot $label (len $label)) -}}
{{- end -}}
{{- if not (regexMatch "^[a-z0-9]" $label) -}}
{{- fail (printf "HostnameLabelInvalid: %s %q must start with a lowercase alphanumeric byte; this chart never normalizes an invalid byte away" $slot $label) -}}
{{- end -}}
{{- if not (regexMatch "[a-z0-9]$" $label) -}}
{{- fail (printf "HostnameLabelInvalid: %s %q must end with a lowercase alphanumeric byte; this chart never normalizes an invalid byte away" $slot $label) -}}
{{- end -}}
{{- if not (regexMatch "^[a-z0-9-]+$" $label) -}}
{{- fail (printf "HostnameLabelInvalid: %s %q may hold only lowercase alphanumerics and internal dashes; this chart never lowercases or strips a byte to make one fit" $slot $label) -}}
{{- end -}}
{{- end -}}

{{/*
  A zone is one or more dot-separated DNS-1123 labels, each judged by the same
  rule as a coordinate slot. Validating the zone as a whole string is what let a
  malformed segment through before: the zone is appended verbatim to the dotted
  name, so a bad segment is a bad hostname label exactly like a bad module is.
*/}}
{{- define "diene-helm-wrapper.dnsZone" -}}
{{- $zone := .zone | toString -}}
{{- if eq $zone "" -}}
{{- fail "HostnameZoneInvalid: the hostname zone is empty; a zone is one or more dot-separated DNS-1123 labels" -}}
{{- end -}}
{{- range $index, $label := splitList "." $zone -}}
{{- include "diene-helm-wrapper.dnsLabel" (dict "slot" (printf "zone label %d of %q" (add1 $index) $zone) "label" $label) -}}
{{- end -}}
{{- end -}}

{{/* Derive ordinary or instance-qualified dotted hostnames. Platform always comes from namespace. */}}
{{- define "diene-helm-wrapper.hostname" -}}
{{- $root := .root -}}
{{- $module := required "hostname module is required" .module | toString -}}
{{- $service := required "hostname service is required" .service | toString -}}
{{- $landscape := required "hostname landscape is required" .landscape | toString -}}
{{/* Verbatim: trimming a leading dot here would repair an invalid zone into valid bytes, which is the one thing this boundary must never do. */}}
{{- $zone := required "hostname zone is required" .zone | toString -}}
{{- $platform := $root.Release.Namespace | toString -}}
{{- $instance := default "" .instance | toString -}}
{{- include "diene-helm-wrapper.dnsLabel" (dict "slot" "module label" "label" $module) -}}
{{- include "diene-helm-wrapper.dnsLabel" (dict "slot" "service label" "label" $service) -}}
{{- include "diene-helm-wrapper.dnsLabel" (dict "slot" "platform label" "label" $platform) -}}
{{- include "diene-helm-wrapper.dnsLabel" (dict "slot" "landscape label" "label" $landscape) -}}
{{- include "diene-helm-wrapper.dnsZone" (dict "zone" $zone) -}}
{{- if $instance -}}
{{- include "diene-helm-wrapper.dnsLabel" (dict "slot" "instance label" "label" $instance) -}}
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
