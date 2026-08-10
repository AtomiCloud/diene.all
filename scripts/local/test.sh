#!/usr/bin/env bash
set -euo pipefail

mode="${1:-}"
coverage="${2:-false}"
watch="${3:-false}"

[ -z "${mode}" ] && echo "❌ test mode not set" >&2 && exit 1
tests="$(yq -r ".tiers.${mode}.tests" .config/go-base.coverage.yaml)"
packages="$(yq -r ".tiers.${mode}.packages" .config/go-base.coverage.yaml)"
# A tier may list several space-separated package patterns (e.g. the meta tier
# runs both its black-box suite and the co-located tests for testhelper's
# internal packages, which Go's internal-import rule keeps under testhelper/).
read -ra test_patterns <<<"${tests}"

if [ "${mode}" = "meta" ] && [ ! -d testhelper ]; then
  echo "✅ Go meta tests skipped: no testhelper package"
  exit 0
fi

if [ "${mode}" = "int" ] && [ ! -d adapters ]; then
  echo "✅ Go int tests skipped: no adapters package"
  exit 0
fi

if [ "${watch}" = "true" ]; then
  gotestsum --watch -- "${test_patterns[@]}"
elif [ "${coverage}" = "true" ]; then
  mkdir -p coverage
  cover_packages="$(go list "${packages}" | paste -sd, -)"
  gotestsum --format pkgname -- -count=1 -covermode=atomic -coverpkg="${cover_packages}" -coverprofile="coverage/${mode}.out" "${test_patterns[@]}"
  ./scripts/validate/go-coverage.sh "${mode}" "coverage/${mode}.out"
else
  gotestsum --format pkgname -- -count=1 "${test_patterns[@]}"
fi

echo "✅ Go ${mode} tests passed"
