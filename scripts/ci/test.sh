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
# nothing in neither.
#
# THIS PATTERN IS THIS NODE'S OWN VALUE. The mechanism is inherited; the value is
# not, and adopting the sibling's verbatim failed loudly rather than silently —
# "❌ meta coverage ledger contains no source files". That is the gate working.
#
# The api-engine sibling keeps its helper code in lib/src/test_helper/{assertions,
# builders,fakes}.dart, so its pattern matched that subtree. diene_e2e has NO
# lib/src/test_helper/ directory at all: it is the family HARNESS, so its helper
# code IS its journey drivers, stub servers and assertions, living in
# lib/src/{assertions,journey,stub}/.
#
# DERIVED FROM THE BARRELS RATHER THAN GUESSED, because the barrels are the
# structural definition of which side a file is on — a file is TestHelper code iff
# `lib/test_helper.dart` exports it, and production code iff `lib/diene_e2e.dart`
# does. Measured at this head:
#   main barrel      -> src/app_handoff/{carrier,wire}.dart          (unit subject)
#   test_helper.dart -> src/assertions/assertions.dart               (meta subject)
#                       src/journey/{journey,deferred_login_journey}.dart
#                       src/stub/{stub_server,app_handoff_stub}.dart
# The measured coverage corroborates the split exactly: the unit run covered
# carrier 40/40 and wire 43/43 and left every helper file at or near zero, because
# the helper files are exercised by the META tier.
#
# lib/test_helper.dart itself is a pure `export` barrel with no executable lines,
# so it contributes nothing either way and is matched into the meta side for
# completeness rather than for coverage.
#
# IF A NEW lib/src SUBTREE IS ADDED it must be added to exactly one side here, and
# the partition-totality assertion below is what forces that rather than letting a
# new directory fall silently into neither ledger.
helper_pattern='(^|/)lib/(test_helper[.]dart|src/(assertions|journey|stub)/.*[.]dart)$'
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

# ### lib-dart-e2e-partition-totality
# #### source: lib/dart/e2e
#
# ASSERT THE PARTITION IS TOTAL. The comment above CLAIMS that every lib/ source
# lands in exactly one ledger; a claim in a comment is not a gate. This proves it
# against the raw pre-filter ledger, so a newly added lib/src subtree cannot fall
# silently into NEITHER side (which is how a whole directory of code stops being
# measured while both tiers stay green).
#
# Refuses on an empty subject rather than reporting clean: "found nothing" and
# "could not look" must not produce the same answer.
partition_report="$(awk -v helper="${helper_pattern}" '
  /^SF:/ {
    path = substr($0, 4)
    if (path !~ /(^|\/)lib\//) next
    total++
    if (path ~ helper) { meta++ } else { unit++ }
  }
  END { printf "%d %d %d", total + 0, unit + 0, meta + 0 }
' "${all_ledger}")"
read -r part_total part_unit part_meta <<<"${partition_report}"
echo "→ ledger partition: ${part_total} lib/ sources = ${part_unit} unit + ${part_meta} meta"
if [[ ${part_total} -eq 0 ]]; then
  echo "❌ REFUSE: the raw coverage ledger names no lib/ sources — cannot judge the partition" >&2
  exit 1
fi
if [[ $((part_unit + part_meta)) -ne ${part_total} ]]; then
  echo "❌ ledger partition is NOT total: ${part_unit} + ${part_meta} != ${part_total}" >&2
  exit 1
fi

rm -f "${all_ledger}"

# ### lib-dart-e2e-coverage-floor
# #### source: lib/dart/e2e
#
# THIS NODE'S UNIT FLOOR IS A TRUE 100%, and that is a MEASUREMENT, not an
# aspiration. The inherited value was api-engine's 571/577 — its measured
# achievable maximum, held below 100% because that package ships GENERATED
# OpenAPI clients and a private constructor whose lines cannot be reached. Adopted
# here it failed loudly ("unit coverage REGRESSED: 188 lines hit, floor is 571"),
# which is the gate correctly refusing to judge this package by another's value.
#
# diene_e2e has no generated code at all. Its unit subject is exactly the two
# app-handoff contract-model files the MAIN barrel exports, and every line of both
# is reached: 83/83, with the uncovered-line enumeration returning EMPTY. So the
# concession api-engine needed does not apply, and taking it anyway would have set
# a floor this package can beat by 495 lines — a gate that cannot fail.
#
# NO EXCLUSIONS AND NO `coverage:ignore` ANYWHERE (R12: two passes, no exclusion
# lists). The floor equals the denominator, so any newly uncovered line drops
# below it and reddens for a real reason.
#
# STANDING OBLIGATION, inherited and kept verbatim in force: THIS FLOOR MAY ONLY
# EVER MOVE UP. Lowering it is a LEAD DECISION requiring its own escalation, never
# a local edit to make a red go away. Since it already sits at 100% the only
# lawful movement is upward with the denominator as code is added.
#
# The META tier is likewise a strict 100% and IS achieved at 173/173. Two lines
# were uncovered when this node's tiers were first measured —
# stub_server.dart's non-object `jsonBody` FormatException and
# app_handoff_stub.dart's `mintingUser` StateError guard. Both were REAL,
# REACHABLE error paths, so they were CLOSED WITH TESTS (each with a positive
# control) rather than excluded or floored around. A reachable guard that nothing
# exercises is a map of a missing test, not a candidate for an exemption.
unit_floor_hit=83
unit_floor_found=83

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
