#!/usr/bin/env bash
set -euo pipefail

mode="${BUILD_MODE:-debug}"
for landscape in lapras pichu pikachu raichu; do
  echo "📦 Building ${landscape} (${mode})..."
  flutter build apk \
    --"${mode}" \
    --flavor "${landscape}" \
    --dart-define="FLUTTER_BASE_LANDSCAPE=${landscape}"
done

echo "✅ All four Flutter flavors built"
