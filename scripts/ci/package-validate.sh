#!/usr/bin/env bash
set -euo pipefail

./scripts/ci/setup.sh
./scripts/validate/dart-package.sh
./scripts/validate/release-policy.sh

echo "📦 Running pub.dev publish dry-run..."
dart pub publish --dry-run

echo "📊 Running pana package analysis..."
dart run pana --exit-code-threshold 0 .

echo "✅ Dart package validation passed"
