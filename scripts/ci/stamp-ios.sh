#!/usr/bin/env bash
set -euo pipefail

in_ipa="${1:-}"
landscape="${2:-}"
build_number="${3:-}"
out_ipa="${4:-}"
version_name="${5:-}"
[ -z "${in_ipa}" ] || [ -z "${landscape}" ] || [ -z "${build_number}" ] || [ -z "${out_ipa}" ] && echo "❌ usage: stamp-ios.sh <in.ipa> <landscape> <build> <out.ipa> [version]" >&2 && exit 1

root="$(cd "$(dirname "$0")/../.." && pwd)"
domain="$(yq '.domain' "${root}/lpsm.yaml")"
platform="$(yq '.platform' "${root}/lpsm.yaml")"
service="$(yq '.service' "${root}/lpsm.yaml")"
new_id="${domain}.${landscape}.${platform}.${service}.app"
app_group="group.${new_id}"
new_name="$(sed -n 's/^BUNDLE_DISPLAY_NAME=\(.*\)$/\1/p' "${root}/ios/Flutter/${landscape}Release.xcconfig")"
[ -z "${new_name}" ] && echo "❌ no release display name for '${landscape}'" >&2 && exit 1

work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT
ipa_dir="${work}/ipa"
scratch="${work}/scratch"
mkdir -p "${ipa_dir}" "${scratch}" "$(dirname "${out_ipa}")"
unzip -qq "${in_ipa}" -d "${ipa_dir}"
app="${ipa_dir}/Payload/Runner.app"
info="${app}/Info.plist"
[ ! -f "${info}" ] && echo "❌ donor IPA has no Payload/Runner.app" >&2 && exit 1

pb() { /usr/libexec/PlistBuddy -c "$1" "$2"; }
pbq() { /usr/libexec/PlistBuddy -c "$1" "$2" 2>/dev/null || true; }

profile="${scratch}/app.mobileprovision"
profile_plist="${scratch}/profile.plist"
for profile_dir in \
  "${HOME}/Library/Developer/Xcode/UserData/Provisioning Profiles" \
  "${HOME}/Library/MobileDevice/Provisioning Profiles"; do
  for candidate in "${profile_dir}"/*.mobileprovision; do
    [ -e "${candidate}" ] || continue
    security cms -D -i "${candidate}" >"${profile_plist}" 2>/dev/null || continue
    candidate_id="$(pbq 'Print :Entitlements:application-identifier' "${profile_plist}")"
    [ "${candidate_id#*.}" != "${new_id}" ] && continue
    cp "${candidate}" "${profile}"
    break 2
  done
done
[ ! -f "${profile}" ] && echo "❌ no provisioning profile found for ${new_id}" >&2 && exit 1

old_id="$(pb 'Print :CFBundleIdentifier' "${info}")"
pb "Set :CFBundleIdentifier ${new_id}" "${info}"
pb "Set :CFBundleName ${new_name}" "${info}"
pbq "Set :CFBundleDisplayName ${new_name}" "${info}"
pb "Set :CFBundleVersion ${build_number}" "${info}"
[ -n "${version_name}" ] && pb "Set :CFBundleShortVersionString ${version_name}" "${info}"
pb "Set :DieneAppGroup ${app_group}" "${info}"
for keypath in \
  ':CFBundleIcons:CFBundlePrimaryIcon:CFBundleIconName' \
  ':CFBundleIcons~ipad:CFBundlePrimaryIcon:CFBundleIconName' \
  ':CFBundleIconName'; do
  current="$(pbq "Print ${keypath}" "${info}")"
  [ -n "${current}" ] && pb "Set ${keypath} AppIcon-${landscape}" "${info}"
done

active_config="${app}/Frameworks/App.framework/flutter_assets/config/raichu.yaml"
[ ! -f "${active_config}" ] && echo "❌ donor IPA lacks selected raichu config asset" >&2 && exit 1
cp "${root}/config/${landscape}.yaml" "${active_config}"

entitlements="${scratch}/app.entitlements"
codesign -d --entitlements - --xml "${app}" >"${entitlements}" 2>/dev/null
plutil -lint "${entitlements}" >/dev/null
current_app_id="$(pb 'Print :application-identifier' "${entitlements}")"
team_id="${current_app_id%%.*}"
pb "Set :application-identifier ${team_id}.${new_id}" "${entitlements}"
pb "Set :com.apple.security.application-groups:0 ${app_group}" "${entitlements}"
cp "${profile}" "${app}/embedded.mobileprovision"

identity="$(security find-identity -v -p codesigning | sed -n 's/.*\([0-9A-F]\{40\}\) "Apple Distribution.*/\1/p' | head -1)"
[ -z "${identity}" ] && echo "❌ no Apple Distribution identity in the keychain" >&2 && exit 1
codesign --force --sign "${identity}" "${app}/Frameworks/App.framework"
codesign --force --sign "${identity}" --entitlements "${entitlements}" "${app}"

rm -f "${out_ipa}"
out_abs="$(cd "$(dirname "${out_ipa}")" && pwd)/$(basename "${out_ipa}")"
(cd "${ipa_dir}" && zip -qry "${out_abs}" .)

codesign --verify --deep --strict "${app}"
[ "$(pb 'Print :CFBundleIdentifier' "${info}")" != "${new_id}" ] && echo "❌ stamp-ios doctor: bundle id drift" >&2 && exit 1
[ "$(pb 'Print :CFBundleVersion' "${info}")" != "${build_number}" ] && echo "❌ stamp-ios doctor: build number drift" >&2 && exit 1
[ "$(pb 'Print :DieneAppGroup' "${info}")" != "${app_group}" ] && echo "❌ stamp-ios doctor: App Group drift" >&2 && exit 1
[ -n "${version_name}" ] && [ "$(pb 'Print :CFBundleShortVersionString' "${info}")" != "${version_name}" ] && echo "❌ stamp-ios doctor: version drift" >&2 && exit 1
codesign -d --entitlements - --xml "${app}" 2>/dev/null | grep -qF "${app_group}" || {
  echo "❌ stamp-ios doctor: signed App Group missing" >&2
  exit 1
}
codesign -d --entitlements - --xml "${app}" 2>/dev/null | grep -qF '<string>*</string>' && echo "❌ stamp-ios doctor: wildcard entitlement leaked" >&2 && exit 1
yq -e ".app.landscape == \"${landscape}\"" "${active_config}" >/dev/null || {
  echo "❌ stamp-ios doctor: baked config is not ${landscape}" >&2
  exit 1
}
packed="$(unzip -Z1 "${out_ipa}")"
for entry in \
  'Payload/Runner.app/embedded.mobileprovision' \
  'Payload/Runner.app/Info.plist' \
  'Payload/Runner.app/Assets.car' \
  'Payload/Runner.app/Frameworks/App.framework/flutter_assets/config/raichu.yaml'; do
  grep -qxF "${entry}" <<<"${packed}" || {
    echo "❌ stamp-ios doctor: packed IPA is missing ${entry}" >&2
    exit 1
  }
done
[ "${old_id}" != "${new_id}" ] && unzip -p "${out_ipa}" Payload/Runner.app/Info.plist | strings | grep -qF "${old_id}" && echo "❌ stamp-ios doctor: donor id remains" >&2 && exit 1

echo "✅ stamp-ios: ${landscape} — ${new_id} build=${build_number} name='${new_name}'"
