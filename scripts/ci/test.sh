#!/usr/bin/env bash
set -euo pipefail

mode="${1:-}"
[[ ${mode} != "unit" && ${mode} != "int" && ${mode} != "sit" ]] && echo "❌ usage: $0 <unit|int|sit>" >&2 && exit 2

root_dir="$(git rev-parse --show-toplevel)"
cd "${root_dir}"

./scripts/ci/setup.sh

config="bunfig.${mode}.toml"
coverage_dir="coverage/${mode}"
coverage_file="${coverage_dir}/lcov.info"
threshold=65
[[ ${mode} == "int" ]] && threshold=30

if [[ ${mode} == "sit" ]]; then
  echo "🧪 Running product-owned SIT coverage journey..."
  bun test --config="${config}" --coverage
  [[ ! -f ${coverage_file} ]] && echo "❌ SIT coverage artifact missing at ${coverage_file}" >&2 && exit 1
  echo "✅ SIT coverage journey passed"
  exit 0
fi

echo "🧪 Running ${mode} tests with coverage..."
rm -rf "${coverage_dir}"

set +e
bun test --config="${config}" --coverage --timeout 120000
test_status=$?
set -e

[[ ! -f ${coverage_file} ]] && echo "❌ No coverage artifact found at ${coverage_file}" >&2 && exit 1

awk -v threshold="${threshold}" '
  BEGIN { files = 0; lines_found = 0; lines_hit = 0; bad = 0 }
  /^SF:/ {
    path = substr($0, 4)
    gsub(/\\\\/, "/", path)
    files++
    if (path ~ "(^|/)tests/") {
      printf "❌ test file present in coverage ledger: %s\n", path > "/dev/stderr"
      bad = 1
    }
  }
  /^LF:/ { lines_found += substr($0, 4) + 0 }
  /^LH:/ { lines_hit += substr($0, 4) + 0 }
  END {
    if (files == 0) {
      print "❌ coverage ledger contains no source files" > "/dev/stderr"
      exit 1
    }
    if (lines_found == 0) {
      print "❌ coverage ledger contains no executable lines" > "/dev/stderr"
      exit 1
    }
    percentage = (lines_hit * 100) / lines_found
    if (percentage < threshold) {
      printf "❌ coverage %.2f%% is below the %d%% tier floor\n", percentage, threshold > "/dev/stderr"
      exit 1
    }
    if (bad != 0) exit 1
  }
' "${coverage_file}"

echo "✅ Coverage artifact meets the ${threshold}% ${mode} tier floor: ${coverage_file}"
[[ ${test_status} -ne 0 ]] && echo "❌ ${mode} tests failed (exit ${test_status})" >&2 && exit "${test_status}"
echo "✅ ${mode} tests passed"
