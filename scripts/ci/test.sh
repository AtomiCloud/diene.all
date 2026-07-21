#!/usr/bin/env bash
set -euo pipefail

mode="${1:-}"
coverage_mode="${2:-no-coverage}"
test_helper_path="${TEST_HELPER_PATH:-lib/test_helper.dart}"
meta_test_path="${META_TEST_PATH:-test/meta}"
[[ ${mode} != "unit" && ${mode} != "meta" ]] && echo "❌ usage: $0 <unit|meta> [coverage|no-coverage]" >&2 && exit 2
[[ ${coverage_mode} != "coverage" && ${coverage_mode} != "no-coverage" ]] && echo "❌ coverage mode must be coverage or no-coverage" >&2 && exit 2

if [[ ${mode} == "meta" && (! -f ${test_helper_path} || ! -d ${meta_test_path}) ]]; then
  echo "✅ Meta tier inactive: this package has no TestHelper"
  exit 0
fi

root_dir="$(git rev-parse --show-toplevel)"
cd "${root_dir}"

./scripts/ci/setup.sh

tests=("${meta_test_path}")
[[ ${mode} == "unit" ]] && tests=(test/unit test/conformance)

if [[ ${coverage_mode} == "no-coverage" ]]; then
  dart test --reporter=expanded "${tests[@]}"
  echo "✅ ${mode} tests passed"
  exit 0
fi

coverage_dir="coverage/${mode}"
raw_dir="${coverage_dir}/raw"
all_ledger="${coverage_dir}/all.info"
ledger="${coverage_dir}/lcov.info"
rm -rf "${coverage_dir}"
mkdir -p "${raw_dir}"

set +e
dart test --reporter=expanded --coverage="${raw_dir}" "${tests[@]}"
test_status=$?
set -e

dart run coverage:format_coverage \
  --lcov \
  --in="${raw_dir}" \
  --out="${all_ledger}" \
  --packages=.dart_tool/package_config.json \
  --report-on=lib

pattern='(^|/)lib/test_helper[.]dart$'
[[ ${mode} == "unit" ]] && pattern='(^|/)lib/src/.*[.]dart$'

awk -v pattern="${pattern}" '
  /^SF:/ { keep = substr($0, 4) ~ pattern }
  keep { print }
' "${all_ledger}" >"${ledger}"
rm -f "${all_ledger}"
rm -rf "${raw_dir}"

awk -v mode="${mode}" '
  BEGIN { files = 0; lines_found = 0; lines_hit = 0 }
  /^SF:/ { files++ }
  /^LF:/ { lines_found += substr($0, 4) + 0 }
  /^LH:/ { lines_hit += substr($0, 4) + 0 }
  END {
    if (files == 0) {
      printf "❌ %s coverage ledger contains no source files\n", mode > "/dev/stderr"
      exit 1
    }
    if (lines_found == 0) {
      printf "❌ %s coverage ledger contains no executable lines\n", mode > "/dev/stderr"
      exit 1
    }
    if (lines_hit != lines_found) {
      printf "❌ %s coverage is not 100%%: %d/%d lines hit\n", mode, lines_hit, lines_found > "/dev/stderr"
      exit 1
    }
    printf "✅ %s coverage is 100%%: %d/%d lines hit\n", mode, lines_hit, lines_found
  }
' "${ledger}"

[[ ${test_status} -ne 0 ]] && echo "❌ ${mode} tests failed (exit ${test_status})" >&2 && exit "${test_status}"
echo "✅ ${mode} coverage artifact: ${ledger}"
