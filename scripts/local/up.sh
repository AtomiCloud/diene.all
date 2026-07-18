#!/usr/bin/env bash
set -euo pipefail

container="diene-go-base-redis"
docker inspect "${container}" >/dev/null 2>&1 && echo "✅ Local dependencies already running" && exit 0
docker run -d --name "${container}" -p 16379:6379 redis:7.4-alpine >/dev/null

echo "✅ Local dependencies started"
