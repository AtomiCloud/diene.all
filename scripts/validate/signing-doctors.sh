#!/usr/bin/env bash
set -euo pipefail

# Fixture id comes from the LPSM grammar, not the pbxproj discovery under test, so target drift fails here.
landscape="$(yq '.landscapes[0].name' lpsm.yaml)"
domain="$(yq '.domain' lpsm.yaml)"
platform="$(yq '.platform' lpsm.yaml)"
service="$(yq '.service' lpsm.yaml)"
[ -z "${landscape}" ] || [ "${landscape}" = "null" ] && echo "❌ lpsm.yaml is missing a landscape for the signing fixture" >&2 && exit 1
[ -z "${domain}" ] || [ "${domain}" = "null" ] && echo "❌ lpsm.yaml is missing domain for the signing fixture" >&2 && exit 1
[ -z "${platform}" ] || [ "${platform}" = "null" ] && echo "❌ lpsm.yaml is missing platform for the signing fixture" >&2 && exit 1
[ -z "${service}" ] || [ "${service}" = "null" ] && echo "❌ lpsm.yaml is missing service for the signing fixture" >&2 && exit 1
app_id="${domain}.${landscape}.${platform}.${service}.app"

fixture_dir="$(mktemp -d)"
trap 'rm -rf "${fixture_dir}"' EXIT
cat >"${fixture_dir}/${landscape}.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict><key>Entitlements</key><dict>
<key>application-identifier</key><string>TEAM.${app_id}</string>
<key>com.apple.security.application-groups</key><array><string>group.${app_id}</string></array>
</dict></dict></plist>
PLIST
DOCTOR_PROFILE_DIR="${fixture_dir}" DOCTOR_PROFILE_FORMAT=plist bash ./scripts/ci/doctor-ios.sh "${landscape}"

for assertion in \
  'bundletool validate' \
  'android:versionCode' \
  'android:label' \
  'jarsigner -verify' \
  'baked config is not'; do
  rg -q "${assertion}" scripts/ci/stamp-android.sh || {
    echo "❌ Android stamp doctor lost '${assertion}'" >&2
    exit 1
  }
done
for assertion in \
  'codesign --verify --deep --strict' \
  'signed App Group missing' \
  'wildcard entitlement leaked' \
  'packed IPA is missing' \
  'baked config is not'; do
  rg -q "${assertion}" scripts/ci/stamp-ios.sh || {
    echo "❌ iOS stamp doctor lost '${assertion}'" >&2
    exit 1
  }
done

echo "✅ signing fixture and post-stamp doctor assertions conform"
