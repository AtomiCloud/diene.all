#!/usr/bin/env bash
set -euo pipefail

mode="${1:-all}"
[ "${mode}" != "publish" ] && [ "${mode}" != "package" ] && [ "${mode}" != "all" ] && echo "❌ mode must be publish, package, or all" >&2 && exit 1

publisher='.github/workflows/reusable-go-publish.yaml'
validator='.github/workflows/reusable-go-lib-validate.yaml'

if [ "${mode}" = "publish" ] || [ "${mode}" = "all" ]; then
  if git -c core.quotePath=false ls-files '.github/workflows/*' | rg '[^\x00-\x7F]' >/dev/null; then
    echo "❌ R-E11 requires ASCII workflow filenames in Go-proxy repositories" >&2
    exit 1
  fi
  [ "$(yq -r '.on.push.tags[0]' .github/workflows/cd.yaml)" != "v*.*.*" ] && echo "❌ CD must trigger on semantic version tags" >&2 && exit 1
  [ "$(yq -r '.jobs.publish.uses' .github/workflows/cd.yaml)" != "./${publisher}" ] && echo "❌ CD publish job is not wired to the reusable publisher" >&2 && exit 1
  [ "$(yq -r '.jobs.publish.secrets' .github/workflows/cd.yaml)" != "inherit" ] && echo "❌ CD publish job must forward secrets: inherit" >&2 && exit 1
  [ ! -f "${publisher}" ] && echo "❌ reusable publisher '${publisher}' is missing" >&2 && exit 1
  rg -F 'scripts/ci/publish.sh' "${publisher}" >/dev/null || {
    echo "❌ reusable publisher does not reach scripts/ci/publish.sh" >&2
    exit 1
  }
  rg -F 'RELEASE_TAG: ${{ github.ref_name }}' "${publisher}" >/dev/null || {
    echo "❌ reusable publisher does not bind RELEASE_TAG to the pushed tag" >&2
    exit 1
  }
  rg -F 'publish.sh "${RELEASE_TAG}"' "${publisher}" >/dev/null || {
    echo "❌ reusable publisher does not propagate RELEASE_TAG into scripts/ci/publish.sh" >&2
    exit 1
  }
  rg -Fx 'releaser release -c atomi_release.yaml -i npm' scripts/ci/release.sh >/dev/null || {
    echo "❌ release job must invoke releaser with the pinned npm runtime" >&2
    exit 1
  }
  rg -F 'writeShellScriptBin "releaser"' nix/packages.nix >/dev/null || {
    echo "❌ releaser bootstrap executable is missing" >&2
    exit 1
  }
  rg -F 'exec ${atomi.sg}/bin/sg "$@"' nix/packages.nix >/dev/null || {
    echo "❌ releaser bootstrap must delegate to sg" >&2
    exit 1
  }
  rg -U 'releaser = \[\n    nodejs\n    releaser\n  \];' nix/env.nix >/dev/null || {
    echo "❌ releaser environment must include pinned node/npm and the releaser bootstrap" >&2
    exit 1
  }
fi

if [ "${mode}" = "package" ] || [ "${mode}" = "all" ]; then
  [ ! -f "${validator}" ] && echo "❌ reusable library validator '${validator}' is missing" >&2 && exit 1
  for job in module-path go-vet api-compatibility export-docs examples; do
    [ "$(yq -r ".jobs.${job}.uses" .github/workflows/ci.yaml)" != "./${validator}" ] && echo "❌ CI job '${job}' is not wired to the library validator" >&2 && exit 1
    [ "$(yq -r ".jobs.${job}.secrets" .github/workflows/ci.yaml)" != "inherit" ] && echo "❌ CI job '${job}' must forward secrets: inherit" >&2 && exit 1
  done
  rg -F 'scripts/ci/pkg-validate.sh' "${validator}" >/dev/null || {
    echo "❌ reusable library validator does not reach scripts/ci/pkg-validate.sh" >&2
    exit 1
  }
  rg -F 'VALIDATION_MODE: ${{ inputs.mode }}' "${validator}" >/dev/null || {
    echo "❌ reusable library validator does not bind the validation mode input" >&2
    exit 1
  }
  rg -F 'pkg-validate.sh "${VALIDATION_MODE}"' "${validator}" >/dev/null || {
    echo "❌ reusable library validator does not propagate the mode into scripts/ci/pkg-validate.sh" >&2
    exit 1
  }
fi

echo "✅ Go library workflow ${mode} wiring passed"
