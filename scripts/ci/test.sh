#!/usr/bin/env bash
set -euo pipefail

dart pub get
dart format --output=none --set-exit-if-changed lib test
dart analyze
./scripts/local/coverage.sh unit
./scripts/local/coverage.sh meta
./scripts/validate/dead-code.sh whole
./scripts/validate/dead-code.sh production
./scripts/validate/publish-version.sh "v$(tr -d '[:space:]' <VERSION)"
dart pub publish --dry-run

echo "✅ Dart package CI passed"
