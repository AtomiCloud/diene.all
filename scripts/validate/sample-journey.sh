#!/usr/bin/env bash
set -euo pipefail

container="diene-go-base-journey-$$"
trap 'docker rm -f "${container}" >/dev/null 2>&1 || true' EXIT

./scripts/local/build.sh
docker run -d --name "${container}" -p 127.0.0.1::6379 redis:7.4-alpine >/dev/null
for _ in $(seq 1 30); do
  docker exec "${container}" redis-cli ping 2>/dev/null | rg -q '^PONG$' && break
  sleep 1
done
port="$(docker port "${container}" 6379/tcp | awk -F: 'END {print $NF}')"
result="$(./dist/go-base note "127.0.0.1:${port}" "Sample Journey" "connected")"
[ "${result}" != "sample-journey=connected" ] && echo "❌ sample journey returned '${result}'" >&2 && exit 1

echo "✅ Sample domain journey passed"
