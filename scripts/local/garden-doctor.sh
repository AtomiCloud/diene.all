#!/usr/bin/env bash
set -euo pipefail

mode="${1:-definition}"
profile="${2:-all}"
installed_file="${DIENE_INSTALLED_FILE:-}"
subset="${DIENE_INSTALLED_SUBSET:-false}"
report_file="${DIENE_DOCTOR_REPORT:-}"

[ "${mode}" != "definition" ] && [ "${mode}" != "installed" ] && echo "❌ doctor mode must be definition or installed" >&2 && exit 1
[ "${mode}" = "installed" ] && [ -z "${installed_file}" ] && echo "❌ 'DIENE_INSTALLED_FILE' env var not set; installed mode compares a real installed tuple against the owning definition" >&2 && exit 1
[ "${mode}" = "installed" ] && [ ! -s "${installed_file}" ] && echo "❌ installed tuple '${installed_file}' not found or empty" >&2 && exit 1

rendered="$(mktemp)"
findings="$(mktemp)"
trap 'rm -f "${rendered}" "${findings}"' EXIT

./scripts/local/garden-render.sh "${profile}" >"${rendered}"

echo "🩺 Garden parity doctor (${mode} mode) over source digest $(jq -r '.sourceDigest' "${rendered}")"

# An omission without a reason is the roster silently shrinking, which is exactly what
# this doctor exists to catch.
jq -r '.profiles | to_entries[] | .key as $p | .value.omitted[] | select(.reason == null) | "\($p)\t\(.id)"' "${rendered}" >"${findings}"
[ -s "${findings}" ] && echo "❌ omitted members without a reason:" >&2 && cat "${findings}" >&2 && exit 1

jq -r '.profiles | to_entries[] | .key as $p | .value.included[] | .id as $m | .images[] | select(.digest == null and .pending == null) | "\($p)\t\($m)\t\(.ref)"' "${rendered}" >"${findings}"
[ -s "${findings}" ] && echo "❌ included images with neither a digest nor a declared pending reason:" >&2 && cat "${findings}" >&2 && exit 1

pending_charts="$(jq -r '[.profiles | to_entries[] | .value.included[] | select(.chartPinned == false)] | length' "${rendered}")"

echo ""
echo "📋 Included members and their pins"
jq -r '.profiles | to_entries[] | "  \(.key) (hosted=\(.value.hosted)):" , (.value.included[] | "    ✔ \(.id) [\(.home)] chart=\(.chart)\(if .chartPinned then "" else " (pin pending)" end)\(if .mode then " mode=" + .mode else "" end)")' "${rendered}"

echo ""
echo "📋 Omissions, each with its reason"
jq -r '.profiles | to_entries[] | "  \(.key):" , (.value.omitted[] | "    ✖ \(.id) — \(.reason)")' "${rendered}"

if [ "${mode}" = "installed" ]; then
  echo ""
  echo "🔍 Comparing installed digests against the owning definitions"
  # A profile may omit a member but never substitute another version, so any installed
  # digest the owning definition does not name is drift.
  jq -r \
    --argjson installed "$(cat "${installed_file}")" \
    --argjson subset "${subset}" \
    '.profiles | to_entries[] | .key as $p | .value.included[] | .id as $m |
       (($installed[$p] // {})[$m] // null) as $live |
       if $live == null then (if $subset then empty else "\($p)\t\($m)\tNOT-INSTALLED\tprofile includes it" end)
       else ( .images | map(select(.digest != null))[] | .digest as $d | (.accepted // [$d]) as $ok |
              select([ (($live.images) // [])[] | select(. as $i | $ok | index($i)) ] | length == 0) |
              "\($p)\t\($m)\tDRIFT\texpected one of \($ok | join(" or "))" )
       end' "${rendered}" >"${findings}"
  [ -s "${findings}" ] && echo "❌ installed digests disagree with the owning definitions:" >&2 && cat "${findings}" >&2 && exit 1
  echo "  every installed member matches the digest its owning definition names"
fi

[ -n "${report_file}" ] && cp "${rendered}" "${report_file}" && echo "📝 Normalized report written to ${report_file}"
[ "${pending_charts}" != "0" ] && echo "⚠️  ${pending_charts} included chart pins are pending Kargo promotion; reported, never assumed"
echo "✅ Garden parity doctor passed in ${mode} mode"
