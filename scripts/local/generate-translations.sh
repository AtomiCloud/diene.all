#!/usr/bin/env bash
set -euo pipefail

echo "🌐 Generating typed translations..."
flutter pub run slang
for file in lib/i18n/*.dart; do
  normalized="$(mktemp)"
  awk '{ sub(/[[:space:]]+$/, ""); print }' "${file}" >"${normalized}"
  mv "${normalized}" "${file}"
done
dart format lib/i18n

echo "✅ Typed translations generated"
