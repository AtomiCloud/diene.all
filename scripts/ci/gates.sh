#!/usr/bin/env bash
# Full Dart-family gate suite for CI (beyond analyze+test in test.sh):
# coverage, meta tier, deadcode both passes, publish dry-run, and the
# manifest==tag guard proven on both its match and mismatch paths.
set -euo pipefail

echo "📊 Coverage..."
dart pub get >/dev/null
dart test --coverage=coverage
dart run coverage:format_coverage --lcov --in=coverage --out=coverage/lcov.info --report-on=lib

echo "🧫 Meta tier (assert-the-asserter)..."
dart test test/meta

echo "🧹 Deadcode pass 1 (whole package)..."
dart analyze

echo "🧹 Deadcode pass 2 (production only)..."
dart analyze lib

echo "📦 Publish dry-run (no upload)..."
dart pub publish --dry-run

echo "🔒 Manifest==tag guard (both paths)..."
./scripts/validate/manifest-tag.sh v0.1.0
if ./scripts/validate/manifest-tag.sh v9.9.9 >/dev/null 2>&1; then
  echo "❌ manifest-tag guard accepted a mismatch" >&2
  exit 1
fi

echo "✅ Dart gate suite passed"
