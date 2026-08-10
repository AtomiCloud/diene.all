#!/usr/bin/env bash
set -euo pipefail

# controller-gen emits a valid-but-weaker CRD when a required marker is absent — docs/domain/operator-conventions.md.

types_dir="api/v1alpha1"
controllers_dir="adapters/operator/controllers"
crd_dir="infra/root_chart/templates/crds"

[ ! -d "${types_dir}" ] && echo "❌ operator marker lint: missing API types directory ${types_dir}" >&2 && exit 1
[ ! -d "${controllers_dir}" ] && echo "❌ operator marker lint: missing controllers directory ${controllers_dir}" >&2 && exit 1
[ ! -d "${crd_dir}" ] && echo "❌ operator marker lint: missing CRD directory ${crd_dir}" >&2 && exit 1

# Facts: type|<Kind>|<marker> · printcolumn|<Kind>|<column> · field|<Type>.<Field>|<marker> · rbac|<controller>|<marker>
required="$(
  cat <<'EOF'
type|Note|kubebuilder:object:root=true
type|Note|kubebuilder:subresource:status
type|Note|kubebuilder:resource:scope=Namespaced,shortName=nt
printcolumn|Note|Category
printcolumn|Note|Copies
printcolumn|Note|Ready
printcolumn|Note|Age
field|NoteSpec.Title|kubebuilder:validation:Required
field|NoteSpec.Title|kubebuilder:validation:MinLength=1
field|NoteSpec.Title|kubebuilder:validation:MaxLength=253
field|NoteSpec.Body|kubebuilder:validation:Required
field|NoteSpec.Body|kubebuilder:validation:MinLength=1
field|NoteSpec.Category|kubebuilder:validation:Required
field|NoteSpec.Category|kubebuilder:validation:Enum=personal;work;archive
field|NoteSpec.Replicas|kubebuilder:validation:Minimum=0
field|NoteSpec.Replicas|kubebuilder:validation:Maximum=50
field|NoteSpec.Replicas|kubebuilder:default=1
field|NoteStatus.Conditions|listType=map
field|NoteStatus.Conditions|listMapKey=type
type|Journal|kubebuilder:object:root=true
type|Journal|kubebuilder:subresource:status
type|Journal|kubebuilder:resource:scope=Namespaced,shortName=jn
printcolumn|Journal|Ready
printcolumn|Journal|Age
field|JournalSpec.Message|kubebuilder:validation:Required
field|JournalSpec.Message|kubebuilder:validation:MinLength=1
field|JournalSpec.Message|kubebuilder:validation:MaxLength=1024
field|JournalStatus.Conditions|listType=map
field|JournalStatus.Conditions|listMapKey=type
rbac|note|groups=sample.diene.atomi.cloud,resources=notes,verbs=get;list;watch;update
rbac|note|groups=sample.diene.atomi.cloud,resources=notes/status,verbs=get;update;patch
rbac|note|groups=sample.diene.atomi.cloud,resources=notes/finalizers,verbs=update
rbac|note|groups="",resources=configmaps,verbs=get;list;watch;create;update;patch;delete
rbac|note|groups="",resources=events,verbs=create;patch
rbac|note|groups=authentication.k8s.io,resources=tokenreviews,verbs=create
rbac|note|groups=authorization.k8s.io,resources=subjectaccessreviews,verbs=create
rbac|note|groups=coordination.k8s.io,resources=leases,verbs=get;create;update
rbac|journal|groups=sample.diene.atomi.cloud,resources=journals,verbs=get;list;watch
rbac|journal|groups=sample.diene.atomi.cloud,resources=journals/status,verbs=get;update;patch
EOF
)"

echo "🔎 extracting kubebuilder markers from ${types_dir} and ${controllers_dir}"

# Each marker block counts only at the declaration it precedes, never file-wide.
facts=""
open='struct {'
for file in "${types_dir}"/*_types.go; do
  [ ! -f "${file}" ] && continue
  scope=""
  inside=0
  pending=""
  while IFS= read -r raw; do
    line="${raw#"${raw%%[![:space:]]*}"}"
    [ -z "${line}" ] && pending="" && continue
    [ "${raw}" = "}" ] && scope="" && inside=0 && pending="" && continue
    [ "${line}" != "${line#// +}" ] && pending="${pending}${line#// +}"$'\n' && continue
    [ "${line}" != "${line#//}" ] && continue
    decl=""
    [ "${line}" != "${line#type }" ] && [ "${line}" != "${line%"${open}"}" ] && scope="${line#type }" && scope="${scope%% *}" && inside=1 && decl="type|${scope}"
    [ "${inside}" = 1 ] && [ -z "${decl}" ] && [ "${line}" != "${line#[A-Z]}" ] && field="${line%% *}" && [ "${field}" = "${field%.*}" ] && decl="field|${scope}.${field}" && facts="${facts}fieldof|${scope}|${field}"$'\n'
    [ -z "${decl}" ] && pending="" && continue
    while IFS= read -r marker; do
      [ -z "${marker}" ] && continue
      facts="${facts}${decl}|${marker}"$'\n'
    done <<<"${pending}"
    pending=""
  done <"${file}"
done

for file in "${controllers_dir}"/*_controller.go; do
  [ ! -f "${file}" ] && continue
  controller="${file##*/}"
  controller="${controller%_controller.go}"
  while IFS= read -r marker; do
    [ -z "${marker}" ] && continue
    facts="${facts}rbac|${controller}|${marker#*+kubebuilder:rbac:}"$'\n'
  done <<<"$(grep -F '+kubebuilder:rbac:' "${file}" || true)"
done

facts="${facts}$(grep -F 'kubebuilder:printcolumn:name=' <<<"${facts}" | sed -E 's/^type\|([^|]+)\|kubebuilder:printcolumn:name="([^"]+)".*/printcolumn|\1|\2/' || true)"$'\n'

echo "🧪 asserting the required marker families"

while IFS= read -r want; do
  [ -z "${want}" ] && continue
  ! grep -qxF "${want}" <<<"${facts}" && echo "❌ operator marker lint: required marker missing → ${want}" >&2 && exit 1
done <<<"${required}"

# The declared grants are the whole grant set, so an unlisted one is a silent privilege addition.
while IFS= read -r got; do
  [ -z "${got}" ] && continue
  ! grep -qxF "${got}" <<<"${required}" && echo "❌ operator marker lint: RBAC marker outside the declared grant set → ${got}" >&2 && exit 1
done <<<"$(grep '^rbac|' <<<"${facts}" || true)"

# A newly served kind must arrive with its own requirement instead of inheriting silence.
while IFS= read -r kind; do
  [ -z "${kind}" ] && continue
  ! grep -qxF "type|${kind}|kubebuilder:subresource:status" <<<"${required}" && echo "❌ operator marker lint: served kind ${kind} has no status-subresource requirement in this gate" >&2 && exit 1
  ! grep -q "^printcolumn|${kind}|" <<<"${required}" && echo "❌ operator marker lint: served kind ${kind} has no print-column requirement in this gate" >&2 && exit 1
done <<<"$(yq -r '.spec.names.kind' "${crd_dir}"/*.yaml | grep -v '^---$' || true)"

while IFS= read -r entry; do
  [ -z "${entry}" ] && continue
  target="${entry#fieldof|}"
  ! grep -q "^field|${target/|/.}|kubebuilder:validation:" <<<"${facts}" && echo "❌ operator marker lint: spec field ${target/|/.} carries no +kubebuilder:validation marker" >&2 && exit 1
done <<<"$(grep -E '^fieldof\|[A-Za-z0-9_]+Spec\|' <<<"${facts}" || true)"

echo "✅ operator marker lint passed"
