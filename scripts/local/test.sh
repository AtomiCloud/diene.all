#!/usr/bin/env bash
set -euo pipefail

mode="${1:-}"
coverage="${2:-false}"
watch="${3:-false}"

[ -z "${mode}" ] && echo "❌ test mode not set" >&2 && exit 1
tests="$(yq -r ".tiers.${mode}.tests" .config/go-base.coverage.yaml)"
packages="$(yq -r ".tiers.${mode}.packages" .config/go-base.coverage.yaml)"

if [ "${mode}" = "meta" ] && ! go list ./testhelper/... >/dev/null 2>&1; then
  echo "✅ Go meta tests skipped: no testhelper package"
  exit 0
fi

if [ "${watch}" = "true" ]; then
  gotestsum --watch -- "${tests}"
elif [ "${coverage}" = "true" ]; then
  mkdir -p coverage
  cover_packages="$(go list "${packages}" | paste -sd, -)"
  gotestsum --format pkgname -- -count=1 -covermode=atomic -coverpkg="${cover_packages}" -coverprofile="coverage/${mode}.out" "${tests}"
  ./scripts/validate/go-coverage.sh "${mode}" "coverage/${mode}.out"
else
  gotestsum --format pkgname -- -count=1 "${tests}"
fi

echo "✅ Go ${mode} tests passed"
