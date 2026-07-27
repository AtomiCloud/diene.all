#!/usr/bin/env bash
set -euo pipefail

# Runs from the repository root. The publishable unit is the workspace member
# packages/diene_config; the root pubspec is the non-published workspace shell.
#
# Every check ASSERTS A VALUE and prints what it compared. Silence is not a
# pass: a guard whose success branch is reached because a command produced no
# output is not a guard, so counts are printed and asserted rather than
# inferred.
root_dir="$(git rev-parse --show-toplevel)"
cd "${root_dir}"

member_dir="packages/diene_config"
member_pubspec="${member_dir}/pubspec.yaml"

[[ -f ${member_pubspec} ]] || {
  echo "❌ member pubspec is missing: ${member_pubspec}" >&2
  exit 1
}

fail=0
bad() {
  printf '❌ %s\n' "$*" >&2
  fail=1
}
expect() { # <label> <actual> <expected>
  local label="$1" got="$2" want="$3"
  printf '  %s = %s\n' "${label}" "${got}"
  [[ ${got} == "${want}" ]] || bad "${label}: expected '${want}', got '${got}'"
}
# `rg` exits 1 when it matches nothing and >1 on a real error. Under
# `set -o pipefail` a naive assignment turned the no-match case — which for the
# forbidden-definition checks below is the PASSING case — into an abort, so the
# gate stopped gating precisely when the code was clean. Only status 1 is
# tolerated here; a genuine ripgrep failure is reported rather than being
# silently read as "zero matches", which would fail open.
rg_out() { # <rg args...>; echoes matching lines, flags a real ripgrep error
  local out status=0
  out="$(rg "$@" 2>/dev/null)" || status=$?
  if [[ ${status} -gt 1 ]]; then
    bad "ripgrep failed with status ${status}: rg $*"
    return 0
  fi
  printf '%s' "${out}"
}

# Identity ------------------------------------------------------------------
echo '→ workspace and package identity'
expect 'root pubspec .name' "$(yq -r '.name' pubspec.yaml)" 'diene_config_workspace'
expect 'root pubspec .publish_to' "$(yq -r '.publish_to' pubspec.yaml)" 'none'
expect 'root pubspec .workspace' "$(yq -r '.workspace | join(",")' pubspec.yaml)" "${member_dir}"
expect 'member .name' "$(yq -r '.name' "${member_pubspec}")" 'diene_config'
expect 'member .version' "$(yq -r '.version' "${member_pubspec}")" "$(tr -d '[:space:]' <VERSION)"
# D1 dart variant: the mirror repo is SNAKED to match the package name.
expect 'member .repository' "$(yq -r '.repository' "${member_pubspec}")" \
  'https://github.com/AtomiCloud/diene.dart_config'
expect 'member .environment.sdk' "$(yq -r '.environment.sdk' "${member_pubspec}")" '>=3.12.0 <4.0.0'
expect 'member .resolution' "$(yq -r '.resolution' "${member_pubspec}")" 'workspace'

# Hosted dependency shape ---------------------------------------------------
# R-E24/R-E12: config consumes core-utils and result as PUBLISHED hosted
# packages, so the real build resolves the same bytes a consumer would. The
# DECLARED CONSTRAINT is asserted here, never the resolved version — pub is
# free to resolve any newer release inside the caret range.
echo '→ hosted runtime dependencies (declared constraints, not resolved versions)'
# diene_problems is a DIRECT dependency, not a transitive one: diene_result
# deliberately does not re-export Problem, and lib/src/config_problem.dart
# constructs Problem values itself.
declare -A expected_deps=(
  [diene_core_utils]='^1.0.0'
  [diene_problems]='^0.1.0'
  [diene_result]='^1.0.0'
  [yaml]='^3.1.3'
)
runtime_deps="$(yq -r '.dependencies // {} | length' "${member_pubspec}")"
expect 'runtime dependency count' "${runtime_deps}" "${#expected_deps[@]}"
for dep in "${!expected_deps[@]}"; do
  expect "dependency ${dep}" \
    "$(yq -r ".dependencies.${dep} // \"ABSENT\"" "${member_pubspec}")" \
    "${expected_deps[${dep}]}"
done

echo '→ no path dependencies and no overrides anywhere'
# A `path:` dependency would publish a package nobody outside this repo can
# resolve, so no dependency value may carry a `path` key.
path_deps="$(yq -r '[((.dependencies // {}) + (.dev_dependencies // {})) | to_entries[] | select((.value | tag) == "!!map") | select(.value | has("path")) | .key] | join(",")' "${member_pubspec}")"
expect 'path dependencies' "${path_deps}" ''
for manifest in pubspec.yaml "${member_pubspec}"; do
  expect "${manifest} has dependency_overrides" \
    "$(yq -r 'has("dependency_overrides")' "${manifest}")" 'false'
done
# An override file must be ABSENT, not merely untracked. An untracked override
# still redirects `dart pub get`, so every local analyze/test/deadcode run would
# bind to bytes a clean consumer will never resolve — the gate would be green
# against a graph that does not exist off this machine. Tracked-ness and
# existence are therefore reported separately and both must be clean.
for override in pubspec_overrides.yaml "${member_dir}/pubspec_overrides.yaml"; do
  if git ls-files --error-unmatch "${override}" >/dev/null 2>&1; then
    bad "${override} is tracked; it must never be committed"
  elif [[ -e ${override} ]]; then
    bad "${override} exists untracked; it redirects resolution away from the hosted graph this gate claims to prove"
  else
    echo "  absent (correct): ${override}"
  fi
done

# Required published and conformance artifacts ------------------------------
# The count is asserted so that shrinking this list is a deliberate edit rather
# than a silently weaker gate.
echo '→ required package artifacts'
required=(
  "${member_dir}/lib/diene_config.dart"
  "${member_dir}/lib/c0_config.dart"
  "${member_dir}/lib/config/app_config.dart"
  "${member_dir}/lib/test_helper.dart"
  # The meta suite is a REQUIRED artifact, not an optional tier: config ships a
  # TestHelper, so a helper without a dogfooding meta test is an incomplete
  # package, and requiring only the helper would let the whole meta proof be
  # deleted while every gate stayed green.
  "${member_dir}/test/meta/test_helper_test.dart"
  "${member_dir}/doc/configuration.md"
  "${member_dir}/example/diene_config_example.dart"
  "${member_dir}/skills/diene-config-usage/SKILL.md"
  "${member_dir}/skills/diene-config-usage/patterns.md"
  "${member_dir}/test/fixtures/c0/config.json"
  "${member_dir}/test/fixtures/c0/SHA256SUMS"
  "${member_dir}/tool/gen_c0_projection.dart"
  "${member_dir}/tool/deadcode_entrypoints.dart"
  "${member_dir}/LICENSE"
  "${member_dir}/README.md"
  "${member_dir}/CHANGELOG.md"
)
present=0
for file in "${required[@]}"; do
  if [[ -f ${file} ]]; then
    present=$((present + 1))
  else
    bad "required package artifact is missing: ${file}"
  fi
done
expect 'artifacts present' "${present}/${#required[@]}" "${#required[@]}/${#required[@]}"

# TestHelper boundary -------------------------------------------------------
# The helper is dependency-light: it ships inside the published package, so a
# test-framework or mocking import would force that dependency on every
# consumer that merely depends on diene_config.
echo '→ TestHelper boundary'
helper_bad_imports="$(rg -c 'package:(test|matcher|mockito|mocktail)/' "${member_dir}/lib/test_helper.dart" || true)"
expect 'test/matcher/mock imports in test_helper.dart' "${helper_bad_imports:-0}" '0'

# No local reimplementation of core-utils primitives ------------------------
# The config node owns YAML reading, layer orchestration, schema/slices and the
# landscape accessor. Merge and environment-key mechanics belong to core-utils;
# a private copy here contradicts the DAG and drifts from C0 §3 silently.
echo '→ core-utils primitives are consumed, not reimplemented'
for forbidden in "${member_dir}/lib/src/deep_merge.dart" "${member_dir}/lib/src/overrides.dart"; do
  if [[ -e ${forbidden} ]]; then
    bad "config must not reimplement a core-utils primitive: ${forbidden}"
  else
    echo "  absent (correct): ${forbidden}"
  fi
done
redefinitions="$(rg_out --no-filename --count-matches \
  -e '\bdeepMerge(All)?\s*\([^)]*\)\s*(=>|\{)' \
  -e '\bcanonicalConfigKey\s*\([^)]*\)\s*(=>|\{)' \
  -e '\bcoerceEnvironmentScalar\s*\([^)]*\)\s*(=>|\{)' \
  -e '\benvironmentToNestedMap\s*\([^)]*\)\s*(=>|\{)' \
  --glob '*.dart' "${member_dir}/lib" | awk '{ n += $0 } END { print n + 0 }')"
expect 'local definitions of core-utils primitives' "${redefinitions}" '0'
# Positive control: every declared diene_* dependency must actually be USED, or
# "no reimplementation" would also be satisfied by a package importing nothing.
# diene_problems is checked here too because diene_result does not re-export
# Problem — config constructs Problem values directly, so a missing import would
# mean the declared constraint is decoration.
for dep in diene_core_utils diene_problems diene_result; do
  # Same hazard, inverted: here zero hits is the FAILURE we want reported, so the
  # count must survive rg's empty-result exit code and still distinguish it from
  # a ripgrep error.
  imports="$(rg_out -l "^import 'package:${dep}/" --glob '*.dart' "${member_dir}/lib" | grep -c . || true)"
  printf '  lib files importing %-18s = %s\n' "${dep}" "${imports}"
  [[ ${imports} -gt 0 ]] || bad "${dep} is declared but never imported; the R-E12 seam is a manifest-only fiction"
done

[[ ${fail} -ne 0 ]] && exit 1

# Frozen C0 source release + projection ------------------------------------
bash ./scripts/validate/c0-release.sh

echo "✅ Dart config identity, hosted-only dependency shape, required artifacts, TestHelper boundary, core-utils consumption, and frozen C0 projection conform"
