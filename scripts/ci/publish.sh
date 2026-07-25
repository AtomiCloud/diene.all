#!/usr/bin/env bash
set -euo pipefail

root_dir="$(git rev-parse --show-toplevel)"
cd "${root_dir}"

[ -z "${NPM_API_KEY:-}" ] && echo "❌ NPM_API_KEY must be set (from the NPM_API_KEY secret)" >&2 && exit 1
[ -z "${GITHUB_REF_NAME:-}" ] && echo "❌ GITHUB_REF_NAME must be set (the pushed tag, e.g. v1.2.3)" >&2 && exit 1

version="${GITHUB_REF_NAME#v}"

# Guard first (fail fast, never mutate): manifest must already carry the tag version.
./scripts/ci/verify-version.sh

./scripts/ci/build.sh

echo "🔐 Writing npm auth token..."
printf '//registry.npmjs.org/:_authToken=%s\n' "${NPM_API_KEY}" >.npmrc

if [ -n "${PUBLISH_DRY_RUN:-}" ]; then
  echo "🧪 DRY RUN: bun publish --access public --tolerate-republish --dry-run"
  bun publish --access public --tolerate-republish --dry-run
  echo "✅ Dry-run publish path exercised for version ${version}"
  exit 0
fi

echo "🚀 Publishing version ${version}..."
bun publish --access public --tolerate-republish

echo "✅ Published version ${version}"
