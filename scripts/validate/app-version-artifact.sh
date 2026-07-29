#!/usr/bin/env bash
set -euo pipefail

# No --build-name/--build-number is passed, so pubspec.yaml is the only possible version source.
# One landscape only: flavor-builds.sh owns the all-four proof, this smoke owns the version contract.

root="$(cd "$(dirname "$0")/../.." && pwd)"
cd "${root}"

version="$(yq '.version' pubspec.yaml)"
expected_name="${version%%+*}"
expected_number="${version##*+}"
[ "${expected_name}" = "${version}" ] || [ "${expected_number}" = "${version}" ] && echo "❌ pubspec version '${version}' is not in <name>+<build> form" >&2 && exit 1

landscape="$(yq '.landscapes[0].name' lpsm.yaml)"
[ -z "${landscape}" ] || [ "${landscape}" = "null" ] && echo "❌ lpsm.yaml declares no landscapes to build" >&2 && exit 1

artifact="build/app/outputs/flutter-apk/app-${landscape}-release.apk"
rm -f "${artifact}"

echo "📦 Building ${landscape} (release) to check the stamped version..."
flutter build apk \
  --release \
  --flavor "${landscape}" \
  --dart-define="FLUTTER_BASE_LANDSCAPE=${landscape}"

[ ! -f "${artifact}" ] && echo "❌ the release build did not emit ${artifact}" >&2 && exit 1

got_name="$(apkanalyzer manifest version-name "${artifact}")"
got_number="$(apkanalyzer manifest version-code "${artifact}")"

[ "${got_name}" != "${expected_name}" ] && echo "❌ release APK versionName '${got_name}' != pubspec '${expected_name}'" >&2 && exit 1
[ "${got_number}" != "${expected_number}" ] && echo "❌ release APK versionCode '${got_number}' != pubspec '${expected_number}'" >&2 && exit 1

echo "✅ ${landscape} release APK reports pubspec version ${version}"
