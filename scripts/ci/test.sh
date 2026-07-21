#!/usr/bin/env bash
set -euo pipefail

echo "🧪 Resolving Dart dependencies..."
dart pub get

echo "🎨 Checking formatting..."
dart format --output=none --set-exit-if-changed lib test

echo "🔍 Analyzing..."
dart analyze

echo "🧫 Running unit, C0-conformance, and meta suites..."
dart test

echo "🧹 Dead-code passes..."
./scripts/validate/deadcode.sh

echo "🏷️  Manifest==tag guard..."
./scripts/validate/manifest-tag.sh check

echo "📦 Package hygiene (publish dry-run)..."
dart pub publish --dry-run

echo "✅ Dart analyze, tests, dead-code, manifest guard, and publish dry-run passed"
