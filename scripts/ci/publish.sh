#!/usr/bin/env bash
set -euo pipefail

tag="${1:-${GITHUB_REF_NAME:-}}"

./scripts/validate/go-publish-guard.sh "${tag}"
./scripts/ci/setup.sh
./scripts/local/build.sh
./scripts/validate/go-proxy-roundtrip.sh "${tag}"

echo "✅ Go module ${tag} is published through the proxy"
