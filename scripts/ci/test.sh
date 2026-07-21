#!/usr/bin/env bash
set -euo pipefail

# Host-safe gate chain for the diene_auth_engine package.

echo "📦 Resolving dependencies..."
flutter pub get

echo "🧹 Format check..."
dart format --output=none --set-exit-if-changed .

echo "🔬 Analyze..."
flutter analyze

echo "🧪 Unit + conformance + meta tests..."
flutter test

echo "📊 Unit coverage ledger..."
flutter test --coverage >/dev/null
bun tool/coverage_ledger.ts coverage/lcov.info unit 80 \
  --include lib/src --exclude test_helper --exclude /logto/

echo "📊 Meta coverage ledger (TestHelper only)..."
flutter test --coverage test/meta >/dev/null
bun tool/coverage_ledger.ts coverage/lcov.info meta 85 --include lib/src/test_helper

echo "☠️  Dead-code (two passes, no exclusion lists)..."
./scripts/validate/deadcode.sh

echo "🏷️  Manifest==tag guard..."
./scripts/validate/manifest-tag.sh

echo "📮 Publish dry-run..."
flutter pub publish --dry-run

echo "✅ All host-safe gates passed"
