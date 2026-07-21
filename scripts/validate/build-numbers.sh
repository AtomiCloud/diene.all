#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=scripts/ci/lib-ios.sh disable=SC1091
source scripts/ci/lib-ios.sh
# shellcheck source=scripts/ci/lib-android.sh disable=SC1091
source scripts/ci/lib-android.sh

fixtures=(
  '0 0 1'
  '10 3 11'
  '10 44 44'
  '44 44 45'
)
for fixture in "${fixtures[@]}"; do
  read -r latest run_number expected <<<"${fixture}"
  [ "$(next_build_number "${latest}" "${run_number}")" != "${expected}" ] && echo "❌ iOS build-number fixture failed: ${fixture}" >&2 && exit 1
  [ "$(next_android_build_number "${latest}" "${run_number}")" != "${expected}" ] && echo "❌ Android build-number fixture failed: ${fixture}" >&2 && exit 1
done

echo "✅ iOS and Android build-number guards passed fixtures"
