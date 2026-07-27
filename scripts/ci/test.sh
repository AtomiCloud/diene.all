#!/usr/bin/env bash
set -euo pipefail

mode="${1:-}"
coverage_mode="${2:-no-coverage}"

# The publishable member lives under packages/diene_e2e (pub workspace).
# `flutter pub get` resolves at the repo root; `flutter test` and its coverage
# collection execute with CWD = the member directory. This member depends on the
# Flutter SDK (transitively, via diene_auth_engine), so the runner is
# `flutter test`, not `dart test` — see
# exec/nodes/lib__dart__e2e/evidence/flutter-toolchain-delta.md.
member_dir="${MEMBER_DIR:-packages/diene_e2e}"
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

# FLUTTER COVERAGE, not the dart + coverage:format_coverage pipeline the pure-Dart
# siblings use. Three reasons, all measured:
#   * `dart test --coverage=<dir>` takes a VALUE while `flutter test --coverage`
#     is a bare FLAG — passing a value fails with 'Flag option "--coverage"
#     should not be given a value.' The blanket dart->flutter invocation
#     migration produced exactly that broken form here before this block landed.
#   * `flutter test --coverage` emits LCOV directly at --coverage-path, so the
#     separate format_coverage conversion is not merely unnecessary but
#     impossible to feed: there is no raw-JSON directory to convert.
#   * `--coverage-package` defaults to the current package name, so only this
#     member's own lib/ is measured and the hosted diene_* deps are excluded
#     without needing --report-on.
# The filtering and the 100% assertion below keep the inherited strictness
# exactly; only the collection mechanism differs.
set +e
flutter test \
  --reporter=expanded \
  --coverage \
  --coverage-path="${all_ledger}" \
  "${tests[@]}"
test_status=$?
set -e

# The two ledgers must PARTITION this package's own Dart sources: production code
# in the unit ledger, TestHelper code in the meta ledger, nothing in both and
# nothing in neither. The inherited patterns assumed the sample's shape, where
# ALL helper code lived in the single file lib/test_helper.dart:
#
#   unit: (^|/)lib/src/.*[.]dart$      meta: (^|/)lib/test_helper[.]dart$
#
# That is wrong for this package. lib/test_helper.dart is a pure barrel of
# `export` directives with NO executable lines, and the real helper code lives in
# lib/src/test_helper/{assertions,builders,fakes}.dart. Under the inherited
# patterns the meta ledger would match a file with nothing in it ("meta coverage
# ledger contains no source files") while the unit ledger silently swallowed all
# the TestHelper code through `lib/src/.*` — inflating the unit denominator with
# helper lines, which the dart-family goal explicitly forbids ("TestHelper
# excluded from the unit ledger").
#
# So `meta` matches the helper subtree plus its barrel, and `unit` matches
# lib/src/ MINUS that subtree.
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

# ### lib-dart-e2e-coverage-floor
# #### source: lib/dart/e2e
#
# THE UNIT FLOOR IS THE MEASURED ACHIEVABLE MAXIMUM, NOT 100%. Ruled by the lead
# after the residue was measured (not predicted) at the landed head.
#
# THE ARGUMENT, which is this session's own law turned around: A GATE THAT IS
# ALWAYS RED DETECTS NOTHING. We spent this session removing gates that could not
# FAIL; a gate that cannot PASS is the same defect wearing the opposite sign — it
# stops being read, and the next person to see it assumes it is noise. A 100%
# threshold on a package shipping GENERATED code and a private constructor is not
# a stricter gate, it is arithmetically unmeetable and therefore permanently
# uninformative.
#
# A floor at the proven-achievable maximum still catches every regression: one
# newly uncovered line drops below it and the gate goes red for a real reason.
# That is strictly MORE detection than 100%-always-red.
#
# THE SIX UNREACHABLE LINES ARE STILL COUNTED IN THE DENOMINATOR — deliberately.
# An exclusion or a `coverage:ignore-file` would delete them from view forever,
# including if the OpenAPI spec later declares the String-returning endpoint that
# would make one of them live. They stay visible, counted, and enumerated in
# exec/nodes/lib__dart__e2e/evidence/CERTIFICATION-*.md.
#
# STANDING OBLIGATION: THIS FLOOR MAY ONLY EVER MOVE UP. Lowering it is a LEAD
# DECISION requiring its own escalation, never a local edit to make a red go away.
# That clause is what stops a measured floor from becoming an exclusion by another
# route. Raise it whenever a line is genuinely closed.
#
# The META tier stays at a strict 100%: its subject is the shipped TestHelper,
# which contains no generated code and no unreachable-by-design members, so 100%
# is achievable there and IS achieved (74/74).
unit_floor_hit=571
unit_floor_found=577

awk -v mode="${mode}" -v floor_hit="${unit_floor_hit}" \
  -v floor_found="${unit_floor_found}" '
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
    if (mode == "meta") {
      # Strict: the TestHelper has no unreachable-by-design surface.
      if (lines_hit != lines_found) {
        printf "❌ meta coverage is not 100%%: %d/%d lines hit\n", lines_hit, lines_found > "/dev/stderr"
        exit 1
      }
      printf "✅ meta coverage is 100%%: %d/%d lines hit\n", lines_hit, lines_found
      exit 0
    }
    # Unit: assert against the measured floor, and print the VALUES compared so
    # the comparison is visible rather than implied.
    printf "ℹ️  unit coverage %d/%d lines hit; floor %d/%d\n", lines_hit, lines_found, floor_hit, floor_found
    if (lines_hit < floor_hit) {
      printf "❌ unit coverage REGRESSED: %d lines hit, floor is %d — a previously covered line is no longer covered\n", lines_hit, floor_hit > "/dev/stderr"
      exit 1
    }
    # A grown denominator with an unchanged hit count means NEW uncovered code.
    if (lines_found > floor_found && lines_hit == floor_hit) {
      printf "❌ unit coverage: %d new executable line(s) added with no new coverage (found %d vs floor %d)\n", lines_found - floor_found, lines_found, floor_found > "/dev/stderr"
      exit 1
    }
    if (lines_hit > floor_hit) {
      printf "✅ unit coverage %d/%d — ABOVE the floor by %d; RAISE unit_floor_hit to %d in scripts/ci/test.sh\n", lines_hit, lines_found, lines_hit - floor_hit, lines_hit
      exit 0
    }
    printf "✅ unit coverage %d/%d lines hit — at the measured floor\n", lines_hit, lines_found
  }
' "${ledger}"

[[ ${test_status} -ne 0 ]] && echo "❌ ${mode} tests failed (exit ${test_status})" >&2 && exit "${test_status}"
echo "✅ ${mode} coverage artifact: ${member_dir}/${ledger}"
