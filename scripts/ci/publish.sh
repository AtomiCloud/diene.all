#!/usr/bin/env bash
set -euo pipefail

./scripts/validate/bun-publish-version.sh
[ -z "${NPM_API_KEY:-}" ] && echo "❌ NPM_API_KEY must be set from the organization secret" >&2 && exit 1

./scripts/ci/setup.sh
./scripts/local/build.sh

printf '//registry.npmjs.org/:_authToken=%s\n' "${NPM_API_KEY}" >.npmrc
trap 'rm -f .npmrc' EXIT

echo "🚀 Publishing version ${GITHUB_REF_NAME#v}..."
bun publish --access public --tolerate-republish

echo "✅ Published version ${GITHUB_REF_NAME#v}"
