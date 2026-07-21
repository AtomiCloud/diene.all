#!/usr/bin/env bash
set -euo pipefail

./scripts/ci/setup.sh
./scripts/validate/dart-publish-version-test.sh
dart analyze
dart test test/c0_release_test.dart test/unit test/conformance
dart test test/meta
./scripts/validate/c0-release.sh

echo "✅ Dart analysis, conformance, unit, and meta tests passed"
