#!/usr/bin/env bash
set -euo pipefail

# pub.dev automated publishing uses GitHub Actions OIDC — there is NO long-lived
# credential to write. Verify the tag/manifest match FIRST (never mutate), then
# publish the member with the OIDC token that GitHub mints for the id-token
# permission the reusable workflow grants.
./scripts/validate/publish-version.sh
./scripts/ci/setup.sh

root_dir="$(git rev-parse --show-toplevel)"
cd "${root_dir}/packages/diene_result"

echo "🚀 Publishing diene_result ${GITHUB_REF_NAME#v} to pub.dev via GitHub Actions OIDC..."
dart pub publish --force

echo "✅ Published diene_result ${GITHUB_REF_NAME#v}"
