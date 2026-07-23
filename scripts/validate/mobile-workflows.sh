#!/usr/bin/env bash
set -euo pipefail

required=(
  .github/workflows/cd.yaml
  .github/workflows/⚡reusable-test.yaml
  .github/workflows/⚡reusable-build-ios.yaml
  .github/workflows/⚡reusable-build-android.yaml
  .github/workflows/⚡reusable-publish-ios.yaml
  .github/workflows/⚡reusable-publish-android.yaml
)
for file in "${required[@]}"; do
  [ ! -f "${file}" ] && echo "❌ missing mobile workflow '${file}'" >&2 && exit 1
done

yq -o=json '.on.workflow_dispatch.inputs.flavor.options' .github/workflows/cd.yaml | jq -e 'index("lapras") != null' >/dev/null || {
  echo "❌ manual CD matrix omits lapras" >&2
  exit 1
}
yq -o=json '.jobs.setup."runs-on"' .github/workflows/cd.yaml | jq -e 'index("nscloud-ubuntu-22.04-amd64-4x8-with-cache") != null' >/dev/null || {
  echo "❌ CD setup is not on the Namespace/Nix runner" >&2
  exit 1
}
rg -q 'scripts/ci/cd-matrix.sh' .github/workflows/cd.yaml || {
  echo "❌ CD setup does not call cd-matrix.sh" >&2
  exit 1
}
rg -q 'scripts/ci/doctor-ios.sh|scripts/ci/publish-ios.sh' .github/workflows/⚡reusable-publish-ios.yaml || {
  echo "❌ iOS publish workflow is not wired to the signing doctor chain" >&2
  exit 1
}
# Parsed, not grepped: a comment or 'ANDROID_KEYSTORE_BASE64: broken' must not satisfy the contract.
android_publish='.github/workflows/⚡reusable-publish-android.yaml'
# shellcheck disable=SC2016 # the literal GitHub expression is the expected value, not a shell expansion
keystore_binding='${{ secrets.ANDROID_KEYSTORE_BASE64 }}'
got_binding="$(yq '.jobs.publish.env.ANDROID_KEYSTORE_BASE64 // ""' "${android_publish}")"
[ "${got_binding}" != "${keystore_binding}" ] && echo "❌ Android publish job must bind ANDROID_KEYSTORE_BASE64 to '${keystore_binding}', got '${got_binding}'" >&2 && exit 1

echo "✅ iOS, Android, and CD matrix workflows are wired"
