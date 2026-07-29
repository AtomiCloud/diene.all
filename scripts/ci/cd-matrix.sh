#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/../.." && pwd)"
lpsm="${root}/lpsm.yaml"
domain="$(yq '.domain' "${lpsm}")"
platform="$(yq '.platform' "${lpsm}")"
service="$(yq '.service' "${lpsm}")"

matrix="$(
  yq -o=json -I=0 '.landscapes' "${lpsm}" |
    jq -c --arg domain "${domain}" --arg platform "${platform}" --arg service "${service}" \
      '[.[] | {flavor: .name, apple_id: (.apple_id // ""), package_name: "\($domain).\(.name).\($platform).\($service).app"}]'
)"

if [ "${EVENT:-}" = "workflow_dispatch" ]; then
  [ -z "${SEL:-}" ] && echo "❌ SEL is required for workflow_dispatch" >&2 && exit 1
  matrix="$(jq -c --arg selected "${SEL}" '[.[] | select(.flavor == $selected)]' <<<"${matrix}")"
  [ "$(jq 'length' <<<"${matrix}")" -ne 1 ] && echo "❌ unknown workflow_dispatch flavor '${SEL}'" >&2 && exit 1
fi

jq -cn --argjson include "${matrix}" '{include: $include}'
