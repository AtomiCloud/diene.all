#!/usr/bin/env bash
set -euo pipefail

donor="raichu"
# shellcheck source=scripts/ci/lib-ios.sh disable=SC1091
source "$(dirname "$0")/lib-ios.sh"

echo "📦 Building the raichu iOS donor..."
flutter pub get
(cd ios && pod install)
keychain initialize
fetch_signing_files "${donor}"
keychain add-certificates
xcode-project use-profiles --export-options-plist "${HOME}/export_options.plist"

build_args=(
  --release
  --flavor "${donor}"
  --build-number=1
  --build-name=1.0.0
  --dart-define=FLUTTER_BASE_LANDSCAPE=raichu
  --export-options-plist="${HOME}/export_options.plist"
)
set +e
./scripts/flutter-ios.sh build ipa "${build_args[@]}"
build_rc=$?
set -e

if ls build/ios/ipa/*.ipa >/dev/null 2>&1; then
  echo "📝 Flutter exported the IPA"
elif [ -d build/ios/archive/Runner.xcarchive ]; then
  echo "📝 Re-exporting the Xcode archive with Apple's rsync"
  while IFS= read -r variable; do unset "${variable}"; done < <(env | sed -n 's/^\(NIX_[A-Za-z0-9_]*\)=.*/\1/p')
  unset CC CXX LD AR NM RANLIB OBJCOPY OBJDUMP STRIP CPP CXXCPP SDKROOT MACOSX_DEPLOYMENT_TARGET LIBRARY_PATH DYLD_LIBRARY_PATH CPATH C_INCLUDE_PATH CPLUS_INCLUDE_PATH
  export DEVELOPER_DIR="${DEVELOPER_DIR_OVERRIDE:-/Applications/Xcode.app/Contents/Developer}"
  export PATH="/usr/bin:/bin:/usr/sbin:/sbin:${PATH}"
  xcodebuild -exportArchive \
    -archivePath build/ios/archive/Runner.xcarchive \
    -exportPath build/ios/ipa \
    -exportOptionsPlist "${HOME}/export_options.plist"
else
  echo "❌ iOS archive was not produced (rc=${build_rc})" >&2
  exit "${build_rc}"
fi

ls build/ios/ipa/*.ipa >/dev/null 2>&1 || {
  echo "❌ iOS donor IPA is missing" >&2
  exit 1
}
echo "✅ iOS donor built"
