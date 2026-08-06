#!/usr/bin/env bash
set -euo pipefail

container="diene-go-base-journey-$$"
status=0
cleanup_status=0
trap 'status=$?; cleanup_status=0; docker rm -f "${container}" >/dev/null 2>&1 || cleanup_status=$?; [ "${status}" -ne 0 ] && exit "${status}"; [ "${cleanup_status}" -ne 0 ] && echo "❌ could not remove sample journey container" >&2 && exit "${cleanup_status}"; true' EXIT

source_result="$(task run -- slug "Sample Journey" | tail -n 1)"
[ "${source_result}" != "sample-journey" ] && echo "❌ source task returned '${source_result}'" >&2 && exit 1
preview_result="$(task preview -- slug "Sample Journey" | tail -n 1)"
[ "${preview_result}" != "sample-journey" ] && echo "❌ preview task returned '${preview_result}'" >&2 && exit 1
docker run -d --name "${container}" -p 127.0.0.1::6379 redis:7.4.5-alpine >/dev/null
# Match the bounded readiness log directly so the script needs no polling loop.
ready="$(timeout 30 rg -m 1 'Ready to accept connections' < <(docker logs -f "${container}" 2>&1) >/dev/null && echo true || echo false)"
[ "${ready}" != "true" ] && echo "❌ redis container never answered PING" >&2 && exit 1
port="$(docker port "${container}" 6379/tcp | awk -F: 'END {print $NF}')"
result="$(./dist/go-base note "127.0.0.1:${port}" "Sample Journey" "connected")"
[ "${result}" != "sample-journey=connected" ] && echo "❌ sample journey returned '${result}'" >&2 && exit 1

echo "✅ Sample domain journey passed"
