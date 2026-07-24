#!/usr/bin/env bash
set -euo pipefail

container="diene-go-base-redis"
docker rm -f "${container}" >/dev/null 2>&1 || true

echo "✅ Local dependencies stopped"
