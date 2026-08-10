#!/usr/bin/env bash
set -euo pipefail

container="diene-go-base-redis"

# Treat only absence of the exact container as a no-op so Docker daemon and permission failures propagate.
existing="$(docker ps --all --quiet --filter "name=^/${container}$")"
[ -z "${existing}" ] && echo "✅ Local dependencies already stopped" && exit 0

docker rm --force "${container}" >/dev/null

echo "✅ Local dependencies stopped"
