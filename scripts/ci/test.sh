#!/usr/bin/env bash
set -euo pipefail

# Host-safe test gate for the Dart library: analyze, both dead-code passes,
# the full test suite, and the two coverage ledgers (unit over product code,
# meta over TestHelper code). The lcov outputs (coverage/unit.lcov,
# coverage/meta.lcov) are produced under distinct names ready for the codecov
# `unit` and `meta` flags.

echo "🧪 Resolving Dart dependencies..."
dart pub get

echo "🔎 Analyze + dead-code pass 1 (whole package, tests included)..."
dart analyze .

echo "🔎 Dead-code pass 2 (library only, no exclusion lists)..."
dart analyze lib

echo "✅ Running full test suite..."
dart test

echo "📊 Unit ledger (product code only)..."
rm -rf coverage/unit
dart test test/unit --coverage=coverage/unit
dart run coverage:format_coverage \
  --packages=.dart_tool/package_config.json \
  --report-on=lib/diene_e2e.dart --report-on=lib/src/app_handoff \
  -i coverage/unit -o coverage/unit.lcov --lcov
./scripts/ci/coverage-report.sh coverage/unit.lcov unit

echo "📊 Meta ledger (TestHelper code only)..."
rm -rf coverage/meta
dart test test/meta --coverage=coverage/meta
dart run coverage:format_coverage \
  --packages=.dart_tool/package_config.json \
  --report-on=lib/test_helper.dart --report-on=lib/src/stub \
  --report-on=lib/src/journey --report-on=lib/src/assertions \
  -i coverage/meta -o coverage/meta.lcov --lcov
./scripts/ci/coverage-report.sh coverage/meta.lcov meta

echo "✅ Dart analyze, tests, and both coverage ledgers passed"
