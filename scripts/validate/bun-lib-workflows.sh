#!/usr/bin/env bash
set -euo pipefail

mode="${1:-}"
[ "${mode}" != "package" ] && [ "${mode}" != "publish" ] && echo "❌ Usage: bun-lib-workflows.sh <package|publish>" >&2 && exit 1

if [ "${mode}" = "package" ]; then
  [ "$(yq -r '.jobs.package-validate.uses' .github/workflows/ci.yaml)" != "./.github/workflows/⚡reusable-package-validate.yaml" ] && echo "❌ package-validate CI job is not wired to its reusable workflow" >&2 && exit 1
  [ "$(yq -r '.jobs.package-validate.permissions.contents' .github/workflows/ci.yaml)" != "read" ] && echo "❌ package-validate caller must grant contents: read" >&2 && exit 1
  [ "$(yq -r '.jobs.package-validate.secrets' .github/workflows/ci.yaml)" != "inherit" ] && echo "❌ package-validate caller must inherit first-party secrets" >&2 && exit 1
  ! rg -q 'scripts/ci/pkg-validate[.]sh' .github/workflows/⚡reusable-package-validate.yaml && echo "❌ package reusable workflow does not reach pkg-validate.sh" >&2 && exit 1
  [ ! -x scripts/ci/pkg-validate.sh ] && echo "❌ pkg-validate.sh is missing or not executable" >&2 && exit 1
  echo "✅ Package validation workflow wiring conforms"
  exit 0
fi

[ "$(yq -r '.jobs.publish.uses' .github/workflows/cd.yaml)" != "./.github/workflows/⚡reusable-publish.yaml" ] && echo "❌ publish CD job is not wired to its reusable workflow" >&2 && exit 1
[ "$(yq -r '.jobs.publish.permissions.contents' .github/workflows/cd.yaml)" != "read" ] && echo "❌ publish caller must grant contents: read" >&2 && exit 1
[ "$(yq -r '.jobs.publish.secrets' .github/workflows/cd.yaml)" != "inherit" ] && echo "❌ publish caller must inherit first-party secrets" >&2 && exit 1
! rg -q 'scripts/ci/publish[.]sh' .github/workflows/⚡reusable-publish.yaml && echo "❌ publish reusable workflow does not reach publish.sh" >&2 && exit 1
[ ! -x scripts/ci/publish.sh ] && echo "❌ publish.sh is missing or not executable" >&2 && exit 1

echo "✅ Publish workflow wiring conforms"
