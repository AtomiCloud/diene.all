#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-}"
[[ ${MODE} != "unit" && ${MODE} != "int" && ${MODE} != "sit" ]] && echo "❌ usage: $0 <unit|int|sit>" >&2 && exit 2

./scripts/ci/setup.sh

# SIT is black-box through the compiled binary — a separate process bun cannot instrument, so no coverage.
if [[ ${MODE} == "sit" ]]; then
  # CI downloads compiled artifacts (actions/download-artifact drops the executable bit) — restore it.
  [[ -d dist/bin ]] && chmod -R +x dist/bin
  [[ -n ${CLI_BIN:-} ]] && chmod +x "${CLI_BIN}"
  echo "🧪 Running sit tests..."
  bun test --config=bunfig.sit.toml
  echo "✅ sit tests passed"
  exit 0
fi

CONFIG="bunfig.${MODE}.toml"
COVERAGE_DIR="coverage/${MODE}"

echo "🧪 Running ${MODE} tests with coverage..."
rm -rf "${COVERAGE_DIR}"

set +e
bun test --config="${CONFIG}" --coverage
test_status=$?
set -e

[[ ! -f ${COVERAGE_DIR}/lcov.info ]] && echo "❌ No coverage artifact found at ${COVERAGE_DIR}/lcov.info" >&2 && exit 1
echo "✅ Coverage artifact: ${COVERAGE_DIR}/lcov.info"

[[ ${test_status} -ne 0 ]] && echo "❌ ${MODE} tests failed (exit ${test_status})" >&2 && exit "${test_status}"
echo "✅ ${MODE} tests passed"
