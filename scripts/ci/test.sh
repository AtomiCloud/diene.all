#!/usr/bin/env bash
set -euo pipefail

mode="${1:-}"
[[ ${mode} != "unit" && ${mode} != "int" && ${mode} != "meta" && ${mode} != "sit" ]] && echo "❌ usage: $0 <unit|int|meta|sit>" >&2 && exit 2

root_dir="$(git rev-parse --show-toplevel)"
cd "${root_dir}"

./scripts/ci/setup.sh

if [[ ${mode} == "sit" ]]; then
  [[ -d dist/bin ]] && chmod -R +x dist/bin
  [[ -n ${CLI_BIN:-} ]] && chmod +x "${CLI_BIN}"
  echo "🧪 Running sit tests..."
  bun test --config=bunfig.sit.toml
  echo "✅ sit tests passed"
  exit 0
fi

config="bunfig.${mode}.toml"
coverage_dir="coverage/${mode}"

rm -rf "${coverage_dir}"

if [[ ${mode} == "meta" ]]; then
  helper_source="$(find src/test-helper -type f -name '*.ts' -print -quit 2>/dev/null || true)"
  meta_test="$(find tests/meta -type f -name '*.test.ts' -print -quit 2>/dev/null || true)"
  [[ -z ${helper_source} && -z ${meta_test} ]] && echo "⏭️ No TestHelper or meta tests exist; meta tier is a successful no-op" && exit 0
  [[ -z ${helper_source} || -z ${meta_test} ]] && echo "❌ TestHelper source and meta tests must be added together" >&2 && exit 1
fi

echo "🧪 Running ${mode} tests with coverage..."

set +e
if [[ ${mode} == "meta" ]]; then
  ./scripts/local/test-meta.sh "${config}" coverage
else
  bun test --config="${config}" --coverage
fi
test_status=$?
set -e

./scripts/local/coverage-check.sh "${mode}"
[[ ${test_status} -ne 0 ]] && echo "❌ ${mode} tests failed (exit ${test_status})" >&2 && exit "${test_status}"
echo "✅ ${mode} tests passed"
