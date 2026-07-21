#!/usr/bin/env bash
set -euo pipefail

tag="${1:-${GITHUB_REF_NAME:-}}"
./scripts/validate/dart-publish-version.sh "$tag"
./scripts/ci/setup.sh
dart pub publish --force

echo "✅ diene_config $tag published"
