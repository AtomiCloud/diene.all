#!/usr/bin/env bash
set -euo pipefail

echo "🧪 Resolving Flutter-backed Dart dependencies..."
flutter pub get

echo "🎨 Checking formatting..."
dart format --output=none --set-exit-if-changed lib test

echo "🔍 Analyzing..."
dart analyze

echo "🧫 Running unit, C0-conformance, and meta suites..."
flutter test

echo "🧹 Dead-code passes..."
./scripts/validate/deadcode.sh

echo "🏷️  Manifest==tag guard..."
./scripts/validate/manifest-tag.sh check

echo "📦 Package hygiene (publish dry-run)..."
./scripts/validate/publish-dry-run.sh

echo "✅ Dart analyze, Flutter tests, dead-code, manifest guard, and publish dry-run passed"
