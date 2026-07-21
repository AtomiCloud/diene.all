#!/usr/bin/env bash
set -euo pipefail

landscape="${1:-}"
[ -z "${landscape}" ] && echo "❌ usage: doctor-ios.sh <landscape>" >&2 && exit 1

targets="$(bash ./scripts/ci/ios-signing-targets.sh "${landscape}")"
[ -z "${targets}" ] && echo "❌ no signable iOS targets discovered" >&2 && exit 1
expected_group="group.${targets%%$'\n'*}"
profile_dirs=(
  "${DOCTOR_PROFILE_DIR:-${HOME}/Library/Developer/Xcode/UserData/Provisioning Profiles}"
  "${HOME}/Library/MobileDevice/Provisioning Profiles"
)
tmp_plist="$(mktemp)"
trap 'rm -f "${tmp_plist}"' EXIT

while IFS= read -r target_id; do
  found=""
  for profile_dir in "${profile_dirs[@]}"; do
    for profile in "${profile_dir}"/*; do
      [ -e "${profile}" ] || continue
      if [ "${DOCTOR_PROFILE_FORMAT:-mobileprovision}" = "plist" ]; then
        cp "${profile}" "${tmp_plist}"
      else
        security cms -D -i "${profile}" >"${tmp_plist}" 2>/dev/null || continue
      fi
      if command -v /usr/libexec/PlistBuddy >/dev/null 2>&1; then
        app_id="$(/usr/libexec/PlistBuddy -c 'Print :Entitlements:application-identifier' "${tmp_plist}" 2>/dev/null || true)"
        groups="$(/usr/libexec/PlistBuddy -c 'Print :Entitlements:com.apple.security.application-groups' "${tmp_plist}" 2>/dev/null || true)"
      else
        app_id="$(rg -o "[A-Z0-9]+\\.${target_id//./\\.}" "${tmp_plist}" | head -1 || true)"
        groups="$(rg -o 'group\.[A-Za-z0-9.-]+' "${tmp_plist}" || true)"
      fi
      [ "${app_id#*.}" != "${target_id}" ] && continue
      found="${profile}"
      grep -qF "${expected_group}" <<<"${groups}" || {
        echo "❌ ${target_id}: profile lacks App Group ${expected_group}" >&2
        exit 1
      }
      echo "🩺 ${target_id} carries ${expected_group}"
      break 2
    done
  done
  [ -z "${found}" ] && echo "❌ no provisioning profile found for ${target_id}" >&2 && exit 1
done <<<"${targets}"

echo "✅ iOS signing profiles passed the App Group doctor"
