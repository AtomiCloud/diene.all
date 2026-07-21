#!/usr/bin/env bash
set -euo pipefail

flutter --version
dart --version
bundletool version
protoc --version
resvg --version
app-store-connect --help >/dev/null
fastlane --version >/dev/null
[ "$(uname -s)" != 'Darwin' ] || pod --version >/dev/null
flutter pub get
dart format --output=none --set-exit-if-changed lib test tool

echo "✅ Flutter toolchain and declared mobile binaries are operational"
