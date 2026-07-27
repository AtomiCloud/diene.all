#!/usr/bin/env bash
set -euo pipefail

# Runs from the repo root. The publishable unit is the workspace member
# packages/diene_auth_engine; the root pubspec is the non-published workspace shell.
root_dir="$(git rev-parse --show-toplevel)"
cd "${root_dir}"

member_dir="packages/diene_auth_engine"
member_pubspec="${member_dir}/pubspec.yaml"

[[ -f ${member_pubspec} ]] || {
  echo "❌ member pubspec is missing: ${member_pubspec}" >&2
  exit 1
}

# Identity ------------------------------------------------------------------
[[ $(yq -r '.name' "${member_pubspec}") != "diene_auth_engine" ]] && echo "❌ member pubspec name must be diene_auth_engine" >&2 && exit 1
[[ $(yq -r '.version' "${member_pubspec}") != "$(cat VERSION)" ]] && echo "❌ member pubspec.yaml version and root VERSION must match" >&2 && exit 1
[[ $(yq -r '.repository' "${member_pubspec}") != "https://github.com/AtomiCloud/diene.dart_auth_engine" ]] && echo "❌ member pubspec repository is not the snaked mirror" >&2 && exit 1

# Runtime dependency shape --------------------------------------------------
# The inherited dart-lib assertion was `-ne 0`, correct for a dependency-free
# SAMPLE and wrong for every real lib. Pin the EXACT count AND every constraint
# (the accepted diene_interfaces shape) so an added or loosened dependency is a
# red gate rather than a silent supply-chain widening.
runtime_deps="$(yq -r '.dependencies // {} | length' "${member_pubspec}")"
[[ ${runtime_deps} -ne 6 ]] && echo "❌ diene_auth_engine must have exactly six runtime dependencies (found ${runtime_deps})" >&2 && exit 1

# Hosted family dependencies (R-E24: hosted deps, never a committed override).
# NOTE the deliberate delta from diene_interfaces, which pins diene_problems
# ^0.1.0: this package pins ^0.1.1 so the solver CANNOT reach 0.1.0, which two
# independent records (R-E24a and 0.1.1's own changelog) declare was published
# from rejected content — while the pub.dev API still reports retracted=false
# for it. The staleness comparison, not the registry flag, is the working
# control.
[[ $(yq -r '.dependencies.diene_result // ""' "${member_pubspec}") != "^1.0.0" ]] && echo "❌ diene_auth_engine must use the hosted diene_result ^1.0.0 contract" >&2 && exit 1
[[ $(yq -r '.dependencies.diene_problems // ""' "${member_pubspec}") != "^0.1.1" ]] && echo "❌ diene_auth_engine must use the hosted diene_problems ^0.1.1 contract (^0.1.0 would admit the rejected 0.1.0)" >&2 && exit 1

# Flutter-package shape. Unlike the four pure-Dart siblings this member depends
# on the Flutter SDK, because logto_dart_sdk requires it. Assert that shape so a
# future edit cannot quietly turn it back into a pure-Dart manifest (which would
# then fail to resolve at all).
[[ $(yq -r '.dependencies.flutter.sdk // ""' "${member_pubspec}") != "flutter" ]] && echo "❌ diene_auth_engine must declare the flutter SDK dependency" >&2 && exit 1
[[ $(yq -r '.environment.flutter // ""' "${member_pubspec}") != ">=3.24.0" ]] && echo "❌ member Flutter SDK constraint must be >=3.24.0" >&2 && exit 1
[[ $(yq -r '.dependencies.logto_dart_sdk // ""' "${member_pubspec}") != "^3.0.0" ]] && echo "❌ diene_auth_engine must use logto_dart_sdk ^3.0.0" >&2 && exit 1
[[ $(yq -r '.dependencies.http // ""' "${member_pubspec}") != "^1.6.0" ]] && echo "❌ diene_auth_engine must use http ^1.6.0" >&2 && exit 1
[[ $(yq -r '.dependencies.meta // ""' "${member_pubspec}") != "^1.16.0" ]] && echo "❌ diene_auth_engine must use meta ^1.16.0" >&2 && exit 1

# pana and test are DELIBERATELY absent from dev_dependencies: a pub workspace
# shares one resolution and neither is solvable against flutter_test's SDK pins.
# Assert their ABSENCE so a well-meaning re-add surfaces as a red gate here
# instead of an opaque solver wall at the next `flutter pub get`.
for forbidden in test pana; do
  if [[ $(yq -r ".dev_dependencies.${forbidden} // \"\"" "${member_pubspec}") != "" ]]; then
    echo "❌ dev_dependency '${forbidden}' is unsolvable alongside flutter_test (test_api/matcher SDK pins); pana runs via 'dart pub global run pana'" >&2
    exit 1
  fi
done
[[ $(yq -r '.dev_dependencies.flutter_test.sdk // ""' "${member_pubspec}") != "flutter" ]] && echo "❌ diene_auth_engine must use flutter_test from the SDK as its test framework" >&2 && exit 1

for override in pubspec_overrides.yaml "${member_dir}/pubspec_overrides.yaml"; do
  if git ls-files --error-unmatch "${override}" >/dev/null 2>&1; then
    echo "❌ ${override} is local-only and must never be committed" >&2
    exit 1
  fi
done
if yq -r 'has("dependency_overrides")' pubspec.yaml | grep -qx true; then
  echo "❌ the committed root pubspec must not carry dependency_overrides" >&2
  exit 1
fi

# Workspace wiring ----------------------------------------------------------
if ! yq -r '.workspace[]' pubspec.yaml | grep -qx "packages/diene_auth_engine"; then
  echo "❌ root pubspec.yaml .workspace must list packages/diene_auth_engine" >&2
  exit 1
fi
[[ $(yq -r '.resolution' "${member_pubspec}") != "workspace" ]] && echo "❌ member pubspec must set resolution: workspace" >&2 && exit 1

# Required published artifacts ----------------------------------------------
for file in \
  "${member_dir}/lib/diene_auth_engine.dart" \
  "${member_dir}/lib/test_helper.dart" \
  "${member_dir}/doc/diene_auth_engine.md" \
  "${member_dir}/skills/diene-auth-engine-usage/SKILL.md" \
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
