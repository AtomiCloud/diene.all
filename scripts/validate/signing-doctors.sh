#!/usr/bin/env bash
set -euo pipefail

fixture_dir="$(mktemp -d)"
trap 'rm -rf "${fixture_dir}"' EXIT
cat >"${fixture_dir}/lapras.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict><key>Entitlements</key><dict>
<key>application-identifier</key><string>TEAM.cloud.atomi.lapras.platform.service.app</string>
<key>com.apple.security.application-groups</key><array><string>group.cloud.atomi.lapras.platform.service.app</string></array>
</dict></dict></plist>
PLIST
DOCTOR_PROFILE_DIR="${fixture_dir}" DOCTOR_PROFILE_FORMAT=plist bash ./scripts/ci/doctor-ios.sh lapras

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
