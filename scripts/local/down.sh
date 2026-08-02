#!/usr/bin/env bash
set -euo pipefail

container="diene-go-base-redis"

# Absence of this exact container is the only tolerated no-op. A listing that
# fails because the daemon is unreachable or the socket is forbidden must not be
# read as "already stopped", so both the listing and the removal propagate.
existing="$(docker ps --all --quiet --filter "name=^/${container}$")"
[ -z "${existing}" ] && echo "✅ Local dependencies already stopped" && exit 0

docker rm --force "${container}" >/dev/null

echo "✅ Local dependencies stopped"
