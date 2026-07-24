#!/usr/bin/env bash
set -euo pipefail

container="diene-go-base-journey-$$"
trap 'docker rm -f "${container}" >/dev/null 2>&1 || true' EXIT

source_result="$(pls run -- slug "Sample Journey" | tail -n 1)"
[ "${source_result}" != "sample-journey" ] && echo "❌ source task returned '${source_result}'" >&2 && exit 1
preview_result="$(pls preview -- slug "Sample Journey" | tail -n 1)"
[ "${preview_result}" != "sample-journey" ] && echo "❌ preview task returned '${preview_result}'" >&2 && exit 1
docker run -d --name "${container}" -p 127.0.0.1::6379 redis:7.4.5-alpine >/dev/null
for _ in $(seq 1 30); do
  docker exec "${container}" redis-cli ping 2>/dev/null | rg -q '^PONG$' && break
  sleep 1
done
port="$(docker port "${container}" 6379/tcp | awk -F: 'END {print $NF}')"
result="$(./dist/go-base note "127.0.0.1:${port}" "Sample Journey" "connected")"
[ "${result}" != "sample-journey=connected" ] && echo "❌ sample journey returned '${result}'" >&2 && exit 1

echo "✅ Sample domain journey passed"
