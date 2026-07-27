#!/usr/bin/env bash
set -euo pipefail

# Runs from the repo root. The publishable unit is the workspace member
# packages/diene_e2e; the root pubspec is the non-published workspace shell.
root_dir="$(git rev-parse --show-toplevel)"
cd "${root_dir}"

member_dir="packages/diene_e2e"
member_pubspec="${member_dir}/pubspec.yaml"

[[ -f ${member_pubspec} ]] || {
  echo "❌ member pubspec is missing: ${member_pubspec}" >&2
  exit 1
}

# Identity ------------------------------------------------------------------
[[ $(yq -r '.name' "${member_pubspec}") != "diene_e2e" ]] && echo "❌ member pubspec name must be diene_e2e" >&2 && exit 1
[[ $(yq -r '.version' "${member_pubspec}") != "$(cat VERSION)" ]] && echo "❌ member pubspec.yaml version and root VERSION must match" >&2 && exit 1
[[ $(yq -r '.repository' "${member_pubspec}") != "https://github.com/AtomiCloud/diene.dart_e2e" ]] && echo "❌ member pubspec repository is not the snaked mirror" >&2 && exit 1

# Runtime dependency shape --------------------------------------------------
# The inherited assertion was `-ne 0`: correct for a dependency-free sample, and
# wrong for any real lib. A parent fix that carries a per-node VALUE must be
# cascaded as a MECHANISM with each node setting its own value and a GATE
# asserting it — so this pins the EXACT count and EVERY constraint by name. A
# silent dependency addition, removal or constraint loosening reddens here.
# These lower bounds are TIGHTENED to the resolved versions, not hand-picked.
# pana's "Compatible with dependency constraint lower bounds" check performs a
# DOWNGRADE analysis, so a constraint whose lower bound cannot build is a promise
# the package cannot keep.
#
# THE VALUE BELOW IS THIS NODE'S OWN, and that distinction is the whole point of
# the mechanism. This gate arrived from the api-engine sibling carrying ITS
# dependency set (collection/dio/json_annotation/retrofit + three diene members,
# count 9). Adopting it byte-identically made it fail immediately — "runtime
# dependencies: 8 (expected 9)" — which is the gate WORKING: it caught that a
# per-node value had been inherited rather than set. The mechanism cascades; the
# value must be local; the gate is what proves the local value is right.
#
# diene_e2e's dependency set is unlike every sibling's because it IS the family
# VERSION TRAIN: it depends on ALL SEVEN members and on nothing else except the
# Flutter SDK. It carries no third-party runtime deps at all — its own source is
# pure `dart:core`/`dart:io`/`dart:convert` — so any third-party addition here is
# a design change that must redden this gate first.
declare -A expected_deps=(
  [diene_api_engine]='^1.0.0'
  [diene_auth_engine]='^1.0.2'
  [diene_config]='^1.0.0'
  [diene_core_utils]='^1.0.1'
  [diene_interfaces]='^1.0.0'
  [diene_problems]='^0.1.1'
  [diene_result]='^1.0.0'
)
# `flutter` is a bare SDK dependency (`sdk: flutter`), not a version constraint,
# so it is counted but its value is checked separately below.
# 7 family members + flutter = 8.
expected_runtime_count=8

# THE TRAIN MUST CARRY EVERY MEMBER. The count above would still pass if a member
# were swapped for a third-party package, so assert the family set by NAME and
# assert the partition is total: every versioned constraint this gate expects is
# a diene_* member, and there are exactly seven of them.
family_members=0
for dep in "${!expected_deps[@]}"; do
  [[ ${dep} == diene_* ]] && family_members=$((family_members + 1))
done
if [[ ${family_members} -ne 7 ]]; then
  echo "❌ the version train must pin all 7 L-dart members (found ${family_members})" >&2
  exit 1
fi
if [[ ${#expected_deps[@]} -ne 7 ]]; then
  echo "❌ diene_e2e must declare no third-party runtime deps (found $((${#expected_deps[@]} - family_members)))" >&2
  exit 1
fi
echo "→ version train pins all 7 L-dart members and 0 third-party runtime deps"

runtime_deps="$(yq -r '.dependencies // {} | length' "${member_pubspec}")"
echo "→ runtime dependencies: ${runtime_deps} (expected ${expected_runtime_count})"
[[ ${runtime_deps} -ne ${expected_runtime_count} ]] && echo "❌ diene_e2e must declare exactly ${expected_runtime_count} runtime dependencies (found ${runtime_deps})" >&2 && exit 1

for dep in "${!expected_deps[@]}"; do
  actual="$(yq -r ".dependencies.${dep} // \"ABSENT\"" "${member_pubspec}")"
  if [[ ${actual} != "${expected_deps[${dep}]}" ]]; then
    echo "❌ dependency ${dep} must be pinned '${expected_deps[${dep}]}' (found '${actual}')" >&2
    exit 1
  fi
done
echo "→ all ${#expected_deps[@]} versioned runtime constraints match their pins"

# The Flutter SDK dependency is what forces this package off the pure-Dart
# toolchain, so its shape is asserted explicitly rather than merely counted.
[[ $(yq -r '.dependencies.flutter.sdk // "ABSENT"' "${member_pubspec}") != "flutter" ]] && echo "❌ dependencies.flutter must be 'sdk: flutter'" >&2 && exit 1
[[ $(yq -r '.environment.flutter // "ABSENT"' "${member_pubspec}") == "ABSENT" ]] && echo "❌ environment must declare a flutter constraint" >&2 && exit 1
[[ $(yq -r '.dev_dependencies.flutter_test.sdk // "ABSENT"' "${member_pubspec}") != "flutter" ]] && echo "❌ dev_dependencies.flutter_test must be 'sdk: flutter'" >&2 && exit 1

# Dev-dependency ABSENCES that a well-meaning re-add would otherwise turn into an
# opaque version-solver wall. Each is unsolvable against flutter_test in this
# shared pub-workspace resolution, or made redundant by the flutter toolchain:
#   test      -> flutter_test re-exports the framework; `test >=1.31.2` pins
#                test_api 0.7.13 while flutter_test pins 0.7.11.
#   pana      -> needs analyzer ^13 / test ^1.26.2; activated into its own
#                isolated resolution by scripts/ci/setup.sh instead.
#   coverage  -> `flutter test --coverage` emits LCOV directly, so there is no
#                raw-JSON directory for coverage:format_coverage to convert.
for forbidden in test pana coverage; do
  present="$(yq -r ".dev_dependencies.${forbidden} // \"ABSENT\"" "${member_pubspec}")"
  if [[ ${present} != "ABSENT" ]]; then
    echo "❌ dev_dependency '${forbidden}' must NOT be declared (found '${present}'): it cannot co-resolve with flutter_test in this pub workspace — see the pubspec comment and the flutter-toolchain delta" >&2
    exit 1
  fi
done
echo "→ dev-dependency absences hold: test, pana, coverage all absent"

# Workspace wiring ----------------------------------------------------------
if ! yq -r '.workspace[]' pubspec.yaml | grep -qx "packages/diene_e2e"; then
  echo "❌ root pubspec.yaml .workspace must list packages/diene_e2e" >&2
  exit 1
fi
[[ $(yq -r '.resolution' "${member_pubspec}") != "workspace" ]] && echo "❌ member pubspec must set resolution: workspace" >&2 && exit 1

# Required published artifacts ----------------------------------------------
for file in \
  "${member_dir}/lib/diene_e2e.dart" \
  "${member_dir}/lib/test_helper.dart" \
  "${member_dir}/doc/diene_e2e.md" \
  "${member_dir}/skills/diene-e2e-usage/SKILL.md" \
  "${member_dir}/LICENSE" \
  "${member_dir}/README.md" \
  "${member_dir}/CHANGELOG.md"; do
  [[ -f ${file} ]] || {
    echo "❌ required package artifact is missing: ${file}" >&2
    exit 1
  }
done

# TestHelper boundary -------------------------------------------------------
if rg -n "package:(test|matcher|mockito|mocktail)/" "${member_dir}/lib/test_helper.dart"; then
  echo "❌ TestHelper must not depend on a test framework or mocking package" >&2
  exit 1
fi

echo "✅ Dart package identity, workspace wiring, artifacts, and TestHelper boundary conform"
