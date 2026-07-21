#!/usr/bin/env bash
set -euo pipefail

landscape="${1:-}"
donor_aab="${2:-}"
[ -z "${landscape}" ] || [ -z "${donor_aab}" ] && echo "❌ usage: publish-android.sh <landscape> <donor.aab>" >&2 && exit 1
[ -z "${ANDROID_KEYSTORE_BASE64:-}" ] && echo "❌ ANDROID_KEYSTORE_BASE64 is required" >&2 && exit 1
# shellcheck source=scripts/ci/lib-android.sh disable=SC1091
source "$(dirname "$0")/lib-android.sh"

keystore_dir="$(mktemp -d)"
trap 'rm -rf "${keystore_dir}"' EXIT
printf '%s' "${ANDROID_KEYSTORE_BASE64}" | base64 -d >"${keystore_dir}/upload.jks"
export ANDROID_KEYSTORE_PATH="${keystore_dir}/upload.jks"
domain="$(yq '.domain' lpsm.yaml)"
platform="$(yq '.platform' lpsm.yaml)"
service="$(yq '.service' lpsm.yaml)"
package_name="${domain}.${landscape}.${platform}.${service}.app"
latest="$(google-play get-latest-build-number --package-name "${package_name}" || echo 0)"
version_code="$(next_android_build_number "${latest:-0}" "${GITHUB_RUN_NUMBER:-0}")"
version_name="$(yq -r '.version' pubspec.yaml | cut -d+ -f1)"
[ "${GITHUB_REF_TYPE:-}" = "tag" ] && version_name="${GITHUB_REF_NAME#v}"

mkdir -p build/app/outputs/stamped
./scripts/ci/stamp-android.sh "${donor_aab}" "${landscape}" "${version_code}" \
  "build/app/outputs/stamped/${landscape}.aab" "${version_name}"

echo "✅ Android ${landscape} artifact is ready to publish"
