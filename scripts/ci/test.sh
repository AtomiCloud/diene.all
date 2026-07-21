#!/usr/bin/env bash
set -euo pipefail

./scripts/ci/setup.sh
./scripts/validate/dart-publish-version-test.sh
dart analyze
dart test test/unit test/conformance
dart test test/meta

echo "✅ Dart analysis, conformance, unit, and meta tests passed"
