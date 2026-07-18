#!/usr/bin/env bash
set -euo pipefail

landscape="${1:-}"
donor_ipa="${2:-}"
[ -z "${landscape}" ] || [ -z "${donor_ipa}" ] && echo "❌ usage: publish-ios.sh <landscape> <donor.ipa>" >&2 && exit 1
# shellcheck source=scripts/ci/lib-ios.sh disable=SC1091
source "$(dirname "$0")/lib-ios.sh"

keychain initialize
fetch_signing_files "${landscape}"
keychain add-certificates
mkdir -p build/ios/stamped
./scripts/ci/stamp-ios.sh "${donor_ipa}" "${landscape}" \
  "$(build_number_for "${landscape}")" \
  "build/ios/stamped/${landscape}.ipa" \
  "$(release_version_name)"

echo "✅ iOS ${landscape} artifact is ready to publish"
