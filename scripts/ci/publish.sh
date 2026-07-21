#!/usr/bin/env bash
# Publishes diene_problems to pub.dev after verifying the manifest==tag guard.
# Runs under CD (tag-triggered) with PUB_CREDENTIALS_JSON already materialized
# by the calling workflow. Execution is conductor-owned; do not run locally.
set -euo pipefail

tag="${1:-${GITHUB_REF_NAME:-}}"
./scripts/validate/manifest-tag.sh "${tag}"
dart pub publish --force

echo "✅ Published diene_problems ${tag}"
