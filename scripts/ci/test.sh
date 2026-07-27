#!/usr/bin/env bash
set -euo pipefail

mode="${1:-}"
coverage_mode="${2:-no-coverage}"

# The publishable member lives under packages/diene_config (pub workspace).
# `dart pub get` resolves at the repo root; `dart test`, coverage collection and
# the coverage:format_coverage run all execute with CWD = the member directory.
member_dir="${MEMBER_DIR:-packages/diene_config}"
test_helper_path="${TEST_HELPER_PATH:-lib/test_helper.dart}"
meta_test_path="${META_TEST_PATH:-test/meta}"

[[ ${mode} != "unit" && ${mode} != "meta" ]] && echo "❌ usage: $0 <unit|meta> [coverage|no-coverage]" >&2 && exit 2
[[ ${coverage_mode} != "coverage" && ${coverage_mode} != "no-coverage" ]] && echo "❌ coverage mode must be coverage or no-coverage" >&2 && exit 2

root_dir="$(git rev-parse --show-toplevel)"
cd "${root_dir}"

# diene_config is a YES-TestHelper library, so its meta tier is MANDATORY, not
# conditional. The inherited template treated the tier as a successful no-op
# whenever the helper or the meta directory was missing; for this package that
# turned deletion of the whole meta suite into a green CI job that uploaded no
# TestHelper coverage at all. Both halves are therefore required, and their
# absence is an error rather than a skip.
#
# TEST_HELPER_PATH/META_TEST_PATH remain overridable so probes can point the
# tier at a deliberately absent path and prove this failure fires.
if [[ ${mode} == "meta" ]]; then
  if [[ ! -f "${member_dir}/${test_helper_path}" ]]; then
    echo "❌ ${member_dir}/${test_helper_path} is missing; diene_config ships a TestHelper and its meta tier is mandatory" >&2
    exit 1
  fi
  if [[ ! -d "${member_dir}/${meta_test_path}" ]]; then
    echo "❌ ${member_dir}/${meta_test_path} is missing; the TestHelper must be dogfooded by a meta suite" >&2
    exit 1
  fi
  meta_test_count="$(find "${member_dir}/${meta_test_path}" -name '*_test.dart' -type f | wc -l)"
  echo "→ meta tier is mandatory; ${meta_test_path} holds ${meta_test_count} test file(s)"
  if [[ ${meta_test_count} -eq 0 ]]; then
    echo "❌ ${member_dir}/${meta_test_path} contains no *_test.dart; an empty meta directory is not a meta suite" >&2
    exit 1
  fi
fi

./scripts/ci/setup.sh

package_config="${root_dir}/.dart_tool/package_config.json"
cd "${root_dir}/${member_dir}"

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
  --packages="${package_config}" \
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
echo "✅ ${mode} coverage artifact: ${member_dir}/${ledger}"
