#!/usr/bin/env bash
set -euo pipefail

mode="${1:-}"
coverage="${2:-false}"
watch="${3:-false}"

[ -z "${mode}" ] && echo "❌ test mode not set" >&2 && exit 1
tests="$(yq -r ".tiers.${mode}.tests" .config/go-base.coverage.yaml)"
packages="$(yq -r ".tiers.${mode}.packages" .config/go-base.coverage.yaml)"

# Watch mode replaces this script so execution cannot fall through to a coverage gate without a profile.
[ "${watch}" = "true" ] && exec gotestsum --watch -- "${tests}"

# Resolve -coverpkg only for coverage runs so plain tests leave no empty coverage output.
[ "${coverage}" = "true" ] && mkdir -p coverage
cover_packages="$([ "${coverage}" = "true" ] && go list "${packages}" | paste -sd, - || echo "")"
coverage_args=()
[ "${coverage}" = "true" ] && coverage_args=(-covermode=atomic -coverpkg="${cover_packages}" -coverprofile="coverage/${mode}.out")

gotestsum --format pkgname -- -count=1 "${coverage_args[@]}" "${tests}"
[ "${coverage}" = "true" ] && ./scripts/validate/go-coverage.sh "${mode}" "coverage/${mode}.out"

echo "✅ Go ${mode} tests passed"
