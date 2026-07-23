#!/usr/bin/env bash
set -euo pipefail

container="diene-go-base-redis"
running="$(docker inspect --format '{{.State.Running}}' "${container}" 2>/dev/null || true)"
[ "${running}" = "true" ] && echo "✅ Local dependencies already running" && exit 0
docker rm -f "${container}" >/dev/null 2>&1 || true
docker run -d --name "${container}" -p 16379:6379 redis:7.4.5-alpine >/dev/null

echo "✅ Local dependencies started"
