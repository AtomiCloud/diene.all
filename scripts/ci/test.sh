#!/usr/bin/env bash
set -euo pipefail

mode="${1:-}"
coverage_mode="${2:-no-coverage}"

# The publishable member lives under packages/diene_auth_engine (pub workspace).
# `flutter pub get` resolves at the repo root; `flutter test`, coverage collection
# and the coverage:format_coverage run all execute with CWD = the member
# directory. This member depends on the Flutter SDK (logto_dart_sdk), so the
# runner is `flutter test`, not `dart test` — see
# exec/nodes/lib__dart__auth-engine/evidence/flutter-toolchain-delta.md.
member_dir="${MEMBER_DIR:-packages/diene_auth_engine}"
test_helper_path="${TEST_HELPER_PATH:-lib/test_helper.dart}"
meta_test_path="${META_TEST_PATH:-test/meta}"

[[ ${mode} != "unit" && ${mode} != "meta" ]] && echo "❌ usage: $0 <unit|meta> [coverage|no-coverage]" >&2 && exit 2
[[ ${coverage_mode} != "coverage" && ${coverage_mode} != "no-coverage" ]] && echo "❌ coverage mode must be coverage or no-coverage" >&2 && exit 2

root_dir="$(git rev-parse --show-toplevel)"
cd "${root_dir}"

# Conditional meta activation: the meta tier is a successful no-op unless BOTH
# the TestHelper source and the meta test directory exist. Presence of exactly
# one is caught by the package-validate identity checks; here we simply skip when
# neither is present so a no-helper fixture stays green.
if [[ ${mode} == "meta" && (! -f "${member_dir}/${test_helper_path}" || ! -d "${member_dir}/${meta_test_path}") ]]; then
  echo "✅ Meta tier inactive: this package has no TestHelper"
  exit 0
fi

./scripts/ci/setup.sh

cd "${root_dir}/${member_dir}"

tests=("${meta_test_path}")
[[ ${mode} == "unit" ]] && tests=(test/unit test/conformance)

if [[ ${coverage_mode} == "no-coverage" ]]; then
  flutter test --reporter=expanded "${tests[@]}"
  echo "✅ ${mode} tests passed"
  exit 0
fi

coverage_dir="coverage/${mode}"
all_ledger="${coverage_dir}/all.info"
ledger="${coverage_dir}/lcov.info"
rm -rf "${coverage_dir}"
mkdir -p "${coverage_dir}"

# FLUTTER COVERAGE, not the dart+coverage:format_coverage pipeline the pure-Dart
# siblings use. Three concrete reasons, all measured:
#   * `dart test --coverage=<dir>` takes a VALUE, while `flutter test --coverage`
#     is a bare FLAG — passing a value fails with "Flag option "--coverage"
#     should not be given a value." (This is exactly how the blanket
#     `dart test` -> `flutter test` migration first broke this gate; the ledger
#     assertion below then failed LOUDLY with "contains no source files" rather
#     than reporting a vacuous pass, which is how it was caught.)
#   * `flutter test --coverage` emits LCOV directly at --coverage-path, so the
#     separate `coverage:format_coverage` conversion is not just unnecessary but
#     impossible to feed — there is no raw-JSON directory to convert.
#   * `--coverage-package` defaults to the current package name, so only this
#     member's own `lib/` is measured; the hosted diene_* deps are excluded
#     without needing --report-on.
# The filtering and the 100% ledger assertion below are UNCHANGED from the
# inherited script — the strictness is identical, only the collection differs.
set +e
flutter test \
  --reporter=expanded \
  --coverage \
  --coverage-path="${all_ledger}" \
  "${tests[@]}"
test_status=$?
set -e

# The two ledgers must PARTITION the package's own Dart sources: production code
# in the unit ledger, TestHelper code in the meta ledger, nothing in both and
# nothing in neither. The inherited patterns assumed the sample's shape, where
# ALL helper code lived in the single file `lib/test_helper.dart`:
#
#   unit: (^|/)lib/src/.*[.]dart$      meta: (^|/)lib/test_helper[.]dart$
#
# That is wrong here. This package's `lib/test_helper.dart` is a pure barrel of
# `export` directives with NO executable lines, and the real helper code lives in
# `lib/src/test_helper/{assertions,builders,fakes}.dart`. Under the inherited
# patterns the meta ledger therefore matched a file with nothing in it ("meta
# coverage ledger contains no source files") while the unit ledger silently
# swallowed all the TestHelper code via `lib/src/.*` — inflating the unit
# denominator with helper lines, which the dart-family goal explicitly forbids
# ("TestHelper excluded from the unit ledger").
#
# So `meta` matches the helper subtree and its barrel, and `unit` matches
# `lib/src/` MINUS that subtree.
helper_pattern='(^|/)lib/(test_helper[.]dart|src/test_helper/.*[.]dart)$'
if [[ ${mode} == "unit" ]]; then
  include='(^|/)lib/src/.*[.]dart$'
  exclude="${helper_pattern}"
else
  include="${helper_pattern}"
  exclude='^$'
fi

# `inc`/`exc`, not `include`/`exclude`: gawk reserves `include` (for @include) and
# dies with "cannot use gawk builtin `include' as variable name".
awk -v inc="${include}" -v exc="${exclude}" '
  /^SF:/ {
    path = substr($0, 4)
    keep = (path ~ inc) && !(path ~ exc)
  }
  keep { print }
' "${all_ledger}" >"${ledger}"
rm -f "${all_ledger}"

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
