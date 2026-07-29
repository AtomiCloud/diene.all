#!/usr/bin/env bash
set -euo pipefail

lpsm="lpsm.yaml"
domain="$(yq '.domain' "${lpsm}")"
platform="$(yq '.platform' "${lpsm}")"
service="$(yq '.service' "${lpsm}")"
flavors="$(yq -o=json -I=0 '[.landscapes[].name]' "${lpsm}")"
count="$(jq 'length' <<<"${flavors}")"

# v1's DoD fixes cardinality and lapras; deriving those too would let a dropped landscape pass.
[ "${count}" -ne 4 ] && echo "❌ lpsm.yaml must declare exactly 4 landscapes, found ${count}" >&2 && exit 1
! jq -e 'index("lapras") != null' <<<"${flavors}" >/dev/null && echo "❌ lpsm.yaml landscapes must include lapras" >&2 && exit 1

matrix="$(EVENT=push bash ./scripts/ci/cd-matrix.sh)"
! jq -e --argjson n "${count}" '.include | length == $n' <<<"${matrix}" >/dev/null && echo "❌ tag CD matrix must contain ${count} landscapes" >&2 && exit 1
! jq -e --argjson flavors "${flavors}" '[.include[].flavor] == $flavors' <<<"${matrix}" >/dev/null && echo "❌ tag CD matrix flavor ordering is invalid" >&2 && exit 1

sel="$(yq '.landscapes[0].name' "${lpsm}")"
sel_apple_id="$(yq '.landscapes[0].apple_id // ""' "${lpsm}")"
sel_package="${domain}.${sel}.${platform}.${service}.app"
manual="$(EVENT=workflow_dispatch SEL="${sel}" bash ./scripts/ci/cd-matrix.sh)"
manual_valid="$(jq --arg flavor "${sel}" --arg apple_id "${sel_apple_id}" --arg package "${sel_package}" \
  '.include == [{flavor: $flavor, apple_id: $apple_id, package_name: $package}]' <<<"${manual}")"
[ "${manual_valid}" != "true" ] && echo "❌ manual CD matrix filtering is invalid" >&2 && exit 1

echo "✅ CD matrix has ${count} tokenized landscapes and manual filtering"
