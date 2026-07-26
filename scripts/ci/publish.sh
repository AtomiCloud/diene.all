#!/usr/bin/env bash
set -euo pipefail

# pub.dev publishing uses the long-lived AtomiCloud org credential
# PUB_CREDENTIALS_JSON, materialized by the calling workflow at
# ${HOME}/.config/dart/pub-credentials.json before this script runs — the shape
# that published diene_problems 0.1.0. Trusted publishing (OIDC) is deliberately
# not used. Verify the tag/manifest match FIRST (never mutate), then publish the
# member.
tag="${1:-${GITHUB_REF_NAME:-}}"

./scripts/validate/publish-version.sh "${tag}"
./scripts/ci/setup.sh

root_dir="$(git rev-parse --show-toplevel)"
cd "${root_dir}/packages/diene_core_utils"

echo "🚀 Publishing diene_core_utils ${tag#v} to pub.dev..."
dart pub publish --force

echo "✅ Published diene_core_utils ${tag#v}"
