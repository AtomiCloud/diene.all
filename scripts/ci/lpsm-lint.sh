#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/../.." && pwd)"
lpsm="${root}/lpsm.yaml"
pbxproj="${root}/ios/Runner.xcodeproj/project.pbxproj"
domain="$(yq '.domain' "${lpsm}")"
platform="$(yq '.platform' "${lpsm}")"
service="$(yq '.service' "${lpsm}")"
landscapes="$(yq '.landscapes[].name' "${lpsm}")"

allowed() {
  local id="${1:?id is required}" landscape
  while IFS= read -r landscape; do
    [[ ${id} =~ ^${domain//./\\.}\.${landscape}\.${platform}\.${service}(\.[a-z][a-z0-9]*)+$ ]] && return 0
  done <<<"${landscapes}"
  return 1
}

while IFS= read -r id; do
  allowed "${id}" || {
    echo "❌ iOS bundle id '${id}' does not derive from lpsm.yaml" >&2
    exit 1
  }
done < <(sed -n 's/^[[:space:]]*PRODUCT_BUNDLE_IDENTIFIER = \([^;]*\);$/\1/p' "${pbxproj}" | rg "^${domain//./\\.}\." | sort -u)

while IFS= read -r id; do
  allowed "${id}" || {
    echo "❌ Android applicationId '${id}' does not derive from lpsm.yaml" >&2
    exit 1
  }
done < <(rg -o 'applicationId = "[^"]+"' "${root}/android/app" -g '*.gradle.kts' | sed 's/.*"\([^"]*\)"/\1/' | sort -u)

while IFS= read -r id; do
  allowed "${id}" || {
    echo "❌ flavorizr id '${id}' does not derive from lpsm.yaml" >&2
    exit 1
  }
done < <(sed -n 's/.*\(bundleId\|applicationId\): \([^ ]*\).*/\2/p' "${root}/pubspec.yaml" | tr -d "'" | sort -u)

while IFS= read -r landscape; do
  app_id="${domain}.${landscape}.${platform}.${service}.app"
  config="${root}/config/${landscape}.yaml"
  [ "$(yq '.app.landscape' "${config}")" != "${landscape}" ] && echo "❌ ${config} has the wrong landscape" >&2 && exit 1
  [ "$(yq '.auth.redirectUri' "${config}")" != "${app_id}://callback" ] && echo "❌ ${config} has a drifted auth redirect" >&2 && exit 1
  [ ! -f "${root}/assets/brand/icon-${landscape}.png" ] && echo "❌ ${landscape} icon is missing" >&2 && exit 1
  rg -q "PRODUCT_BUNDLE_IDENTIFIER = ${app_id//./\\.};" "${pbxproj}" || {
    echo "❌ ${landscape} has no Xcode app configuration" >&2
    exit 1
  }
  rg -q "FLUTTER_BASE_APP_GROUP=group\.${app_id//./\\.}" "${root}/ios/Flutter/${landscape}"*.xcconfig || {
    echo "❌ ${landscape} App Group build setting is missing" >&2
    exit 1
  }
done <<<"${landscapes}"

yq -o=json '.capabilities.app' "${lpsm}" | jq -e 'index("app-group") != null' >/dev/null || {
  echo "❌ app capability must include app-group" >&2
  exit 1
}
rg -q '\$\(FLUTTER_BASE_APP_GROUP\)' "${root}/ios/Runner/Runner.entitlements" || {
  echo "❌ Runner.entitlements is not driven by FLUTTER_BASE_APP_GROUP" >&2
  exit 1
}
identity_scripts=(
  scripts/ci/cd-matrix.sh
  scripts/ci/ios-signing-targets.sh
  scripts/ci/stamp-android.sh
  scripts/ci/stamp-ios.sh
  scripts/ci/publish-android.sh
)
for script in "${identity_scripts[@]}"; do
  rg -q "yq ['\"]?\.domain|domain=\"?\$\(yq '\.domain'" "${root}/${script}" || {
    echo "❌ ${script} does not derive the domain from lpsm.yaml" >&2
    exit 1
  }
  if rg -n 'cloud\.atomi\.' "${root}/${script}"; then
    echo "❌ ${script} hardcodes the domain prefix" >&2
    exit 1
  fi
done

echo "✅ LPSM identities, redirects, icons, and capabilities conform"
