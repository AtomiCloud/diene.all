#!/usr/bin/env bash
set -euo pipefail

tag="${1:-${GITHUB_REF_NAME:-}}"
./scripts/validate/publish-version.sh "${tag}"
dart pub publish --force
