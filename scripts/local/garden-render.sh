#!/usr/bin/env bash
set -euo pipefail

profile="${1:-all}"
members_dir="${DIENE_MEMBERS_DIR:-sulfoxide/members}"
profiles_file="${DIENE_PROFILES_FILE:-sulfoxide/profiles.yaml}"
import_file="${DIENE_IMPORT_FILE:-sulfoxide/import.yaml}"
use_fixtures="${DIENE_PARITY_FIXTURES:-false}"

[ ! -d "${members_dir}" ] && echo "❌ member definition directory '${members_dir}' not found" >&2 && exit 1
[ ! -f "${profiles_file}" ] && echo "❌ profile registry '${profiles_file}' not found" >&2 && exit 1
[ ! -f "${import_file}" ] && echo "❌ import pointer '${import_file}' not found" >&2 && exit 1

echo "📦 Reading owning member definitions from ${members_dir}" >&2

# Garden consumes the owning definitions directly. The imported half is resolved from the
# pointer in import.yaml; only an explicit fixture opt-in may stand in for it.
import_state="$(yq -r '.primordial.state' "${import_file}")"
import_dir=""
if [ "${import_state}" = "pending" ]; then
  [ "${use_fixtures}" != "true" ] && echo "❌ Primordial member export is pending; set DIENE_PARITY_FIXTURES=true to render against the fenced fixture set" >&2 && exit 1
  import_dir="$(yq -r '.primordial.fixtures' "${import_file}")"
  echo "🧪 Primordial export pending: rendering against fixtures in ${import_dir}" >&2
else
  import_dir="$(yq -r '.primordial.path' "${import_file}")"
fi
[ ! -d "${import_dir}" ] && echo "❌ imported member directory '${import_dir}' not found" >&2 && exit 1

sources="$(mktemp)"
normalized="$(mktemp)"
trap 'rm -f "${sources}" "${normalized}"' EXIT

find "${members_dir}" "${import_dir}" -maxdepth 1 -name '*.yaml' -print0 | sort -z | xargs -0 yq ea -o=json '[.]' >"${sources}"
source_digest="$(find "${members_dir}" "${import_dir}" -maxdepth 1 -name '*.yaml' -print0 | sort -z | xargs -0 cat | sha256sum | cut -d' ' -f1)"

jq -e 'length > 0' "${sources}" >/dev/null || {
  echo "❌ no member definitions were read" >&2
  exit 1
}

# Union uniqueness (ENV-SPEC reconciliation 1): one member, one home, one definition.
duplicates="$(jq -r 'group_by(.id) | map(select(length > 1)) | map(.[0].id) | join(", ")' "${sources}")"
[ -n "${duplicates}" ] && echo "❌ member ids are authored more than once: ${duplicates}" >&2 && exit 1

profile_list="$(yq -o=json '[.profiles[].id]' "${profiles_file}")"
[ "${profile}" != "all" ] && ! echo "${profile_list}" | jq -e --arg p "${profile}" 'index($p)' >/dev/null && echo "❌ unknown profile '${profile}'" >&2 && exit 1

selected="${profile_list}"
[ "${profile}" != "all" ] && selected="$(jq -n --arg p "${profile}" '[$p]')"

jq -n \
  --argjson members "$(cat "${sources}")" \
  --argjson profiles "${selected}" \
  --argjson registry "$(yq -o=json '.' "${profiles_file}")" \
  --arg digest "${source_digest}" \
  '{
     schema: "diene-garden-parity-report/v1",
     sourceDigest: $digest,
     memberCount: ($members | length),
     profiles: (
       $profiles | map(. as $p | {
         key: $p,
         value: {
           hosted: ($registry.profiles | map(select(.id == $p))[0].hosted),
           included: ($members | map(select(.profiles[$p].state == "include")) | map({
             id, home, owner,
             mode: (.profiles[$p].mode // null),
             chart: (if .chartRef.digest == null then (.chartRef.repository + ":" + .chartRef.version) else (.chartRef.repository + "@" + .chartRef.digest) end),
             chartPinned: (.chartRef.digest != null),
             images: (.imageRefs | map(if .digest == null then {ref, digest: null, pending} else {ref, digest, accepted: ([.digest] + (.platformDigests // []))} end))
           }) | sort_by(.id)),
           omitted: ($members | map(select(.profiles[$p].state == "omit")) | map({id, home, reason: .profiles[$p].reason}) | sort_by(.id))
         }
       }) | from_entries
     )
   }' >"${normalized}"

cat "${normalized}"
echo "✅ Rendered ${profile} baseline from the owning definitions (source digest ${source_digest})" >&2
