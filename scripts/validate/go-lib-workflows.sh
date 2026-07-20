#!/usr/bin/env bash
set -euo pipefail

mode="${1:-all}"
[ "${mode}" != "publish" ] && [ "${mode}" != "package" ] && [ "${mode}" != "all" ] && echo "❌ mode must be publish, package, or all" >&2 && exit 1

if [ "${mode}" = "publish" ] || [ "${mode}" = "all" ]; then
  [ "$(yq -r '.on.push.tags[0]' .github/workflows/cd.yaml)" != "v*.*.*" ] && echo "❌ CD must select semantic version tags" >&2 && exit 1
  [ "$(yq -r '.jobs.publish.uses' .github/workflows/cd.yaml)" != "./.github/workflows/reusable-go-publish.yaml" ] && echo "❌ CD publish job is not wired to the reusable publisher" >&2 && exit 1
  rg -F 'scripts/ci/publish.sh' .github/workflows/reusable-go-publish.yaml >/dev/null || {
    echo "❌ reusable publisher does not reach scripts/ci/publish.sh" >&2
    exit 1
  }
fi

if [ "${mode}" = "package" ] || [ "${mode}" = "all" ]; then
  for job in module-path go-vet api-compatibility export-docs examples; do
    [ "$(yq -r ".jobs.${job}.uses" .github/workflows/ci.yaml)" != "./.github/workflows/reusable-go-lib-validate.yaml" ] && echo "❌ CI job '${job}' is not wired to the library validator" >&2 && exit 1
  done
  rg -F 'scripts/ci/pkg-validate.sh' .github/workflows/reusable-go-lib-validate.yaml >/dev/null || {
    echo "❌ reusable library validator does not reach scripts/ci/pkg-validate.sh" >&2
    exit 1
  }
fi

echo "✅ Go library workflow ${mode} wiring passed"
