#!/usr/bin/env bash
set -euo pipefail

# Runs from the repository root. The publishable unit is the workspace member
# packages/diene_core_utils; the root pubspec is the non-published workspace
# shell.
root_dir="$(git rev-parse --show-toplevel)"
cd "${root_dir}"

member_dir="packages/diene_core_utils"
member_pubspec="${member_dir}/pubspec.yaml"

[[ -f ${member_pubspec} ]] || {
  echo "❌ member pubspec is missing: ${member_pubspec}" >&2
  exit 1
}

# Identity ------------------------------------------------------------------
[[ $(yq -r '.name' pubspec.yaml) != "diene_core_utils_workspace" ]] && echo "❌ root pubspec name must be diene_core_utils_workspace" >&2 && exit 1
[[ $(yq -r '.name' "${member_pubspec}") != "diene_core_utils" ]] && echo "❌ member pubspec name must be diene_core_utils" >&2 && exit 1
[[ $(yq -r '.version' "${member_pubspec}") != "$(tr -d '[:space:]' <VERSION)" ]] && echo "❌ member pubspec.yaml version and root VERSION must match" >&2 && exit 1
# D1 dart variant: the mirror repo is SNAKED to match the package name.
[[ $(yq -r '.repository' "${member_pubspec}") != "https://github.com/AtomiCloud/diene.dart_core_utils" ]] && echo "❌ member pubspec repository is not the snaked mirror" >&2 && exit 1
[[ $(yq -r '.environment.sdk' "${member_pubspec}") != ">=3.12.0 <4.0.0" ]] && echo "❌ member Dart SDK constraint must be >=3.12.0 <4.0.0" >&2 && exit 1

# Hosted family dependencies (R-E24: hosted deps, never a committed override) --
# R-E12: diene_result AND diene_interfaces are consumed as PUBLISHED hosted
# packages, so the real build resolves the same bytes a consumer would.
runtime_deps="$(yq -r '.dependencies // {} | length' "${member_pubspec}")"
[[ ${runtime_deps} -ne 4 ]] && echo "❌ diene_core_utils must have exactly four runtime dependencies (found ${runtime_deps})" >&2 && exit 1
declare -A expected_deps=(
  [diene_interfaces]='^1.0.0'
  [diene_problems]='^0.1.0'
  [diene_result]='^1.0.0'
  [unorm_dart]='^0.3.2'
)
for dep in "${!expected_deps[@]}"; do
  actual="$(yq -r ".dependencies.${dep} // \"\"" "${member_pubspec}")"
  if [[ ${actual} != "${expected_deps[${dep}]}" ]]; then
    echo "❌ dependency ${dep} must be ${expected_deps[${dep}]}, found '${actual}'" >&2
    exit 1
  fi
  echo "  ✓ ${dep} ${actual}"
done
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
if yq -r 'has("dependency_overrides")' "${member_pubspec}" | grep -qx true; then
  echo "❌ the committed member pubspec must not carry dependency_overrides" >&2
  exit 1
fi

# Platform neutrality ------------------------------------------------------
# This package is pure: it reaches the outside world ONLY through the injected
# diene_interfaces Vfs seam, never a host API. That is what keeps it usable on
# the web and on Flutter, and what keeps pana's platform score perfect.
if rg -n "^import 'dart:io'|package:flutter/|package:path/" "${member_dir}/lib"; then
  echo "❌ diene_core_utils must not depend on dart:io, Flutter, or package:path" >&2
  exit 1
fi
for forbidden in "${member_dir}/lib/src/problem.dart" "${member_dir}/lib/src/result.dart"; do
  [[ -e ${forbidden} ]] && echo "❌ diene_core_utils must not define a competing ${forbidden##*/} type" >&2 && exit 1
done
# The seam must be consumed through the published INTERFACE, not re-declared.
if ! rg -q "^import 'package:diene_interfaces/diene_interfaces.dart';" "${member_dir}/lib/src/vfs_config.dart"; then
  echo "❌ the Vfs seam helpers must import the published diene_interfaces contract" >&2
  exit 1
fi
if rg -n 'class .*implements Vfs' "${member_dir}/lib"; then
  echo "❌ diene_core_utils must not ship a concrete Vfs implementation (S33 item 6)" >&2
  exit 1
fi
# RB-19: no trace seam, and no OTel implementer or exporter.
if rg -ni 'tracer|opentelemetry|package:opentelemetry' "${member_dir}/lib"; then
  echo "❌ diene_core_utils owns no trace seam and no OTel implementer (RB-19)" >&2
  exit 1
fi
# C0 §2: every type URI comes from the ONE builder, never a hand-formatted string.
if rg -n 'https?://[^ ]*/docs/' "${member_dir}/lib"; then
  echo "❌ problem type URIs must be minted by problemTypeUri, never hand-formatted (C0 §2)" >&2
  exit 1
fi
if ! rg -q 'problemTypeUri\(' "${member_dir}/lib/src/util_problem.dart"; then
  echo "❌ util_problem.dart must mint its type URIs through problemTypeUri (C0 §2)" >&2
  exit 1
fi

# Workspace wiring ----------------------------------------------------------
if ! yq -r '.workspace[]' pubspec.yaml | grep -qx "${member_dir}"; then
  echo "❌ root pubspec.yaml .workspace must list ${member_dir}" >&2
  exit 1
fi
[[ $(yq -r '.resolution' "${member_pubspec}") != "workspace" ]] && echo "❌ member pubspec must set resolution: workspace" >&2 && exit 1

# Required published and conformance artifacts -----------------------------
for file in \
  "${member_dir}/lib/diene_core_utils.dart" \
  "${member_dir}/lib/c0_temporal.dart" \
  "${member_dir}/doc/core_utils.md" \
  "${member_dir}/example/diene_core_utils_example.dart" \
  "${member_dir}/skills/diene-core-utils-usage/SKILL.md" \
  "${member_dir}/skills/diene-core-utils-usage/patterns.md" \
  "${member_dir}/test/fixtures/c0/config.json" \
  "${member_dir}/test/fixtures/c0/SHA256SUMS" \
  "${member_dir}/tool/gen_c0_projection.dart" \
  "${member_dir}/tool/gen_iana_zones.dart" \
  "${member_dir}/tool/iana_source.dart" \
  "${member_dir}/tool/deadcode_entrypoints.dart" \
  "${member_dir}/LICENSE" \
  "${member_dir}/README.md" \
  "${member_dir}/CHANGELOG.md"; do
  [[ -f ${file} ]] || {
    echo "❌ required package artifact is missing: ${file}" >&2
    exit 1
  }
done

# TestHelper NO-verdict -----------------------------------------------------
# The family goal records a NO verdict for core-utils: its members are pure
# functions with nothing to fake and no assertion a consumer would repeat, so
# shipping a helper would add surface without helping anyone. This is asserted,
# not merely omitted, so a future addition is a deliberate decision that has to
# change this gate and the goal row together.
if [[ -e "${member_dir}/lib/test_helper.dart" ]]; then
  echo "❌ core-utils carries a NO TestHelper verdict (goals/lib/dart-family.md);" >&2
  echo "   adding lib/test_helper.dart requires changing the goal row first" >&2
  exit 1
fi
if [[ -d "${member_dir}/test/meta" ]]; then
  echo "❌ the meta tier has no subject here: there is no TestHelper to test" >&2
  exit 1
fi
# The NO verdict is carried by the shipped skill instead, per the family rule.
if ! rg -qi 'test.?helper' "${member_dir}/skills/diene-core-utils-usage/SKILL.md" "${member_dir}/skills/diene-core-utils-usage/patterns.md"; then
  echo "❌ the shipped skill must explain the meta convention and how to create a" >&2
  echo "   TestHelper for this lib when one is genuinely needed (family rule)" >&2
  exit 1
fi
# And the meta runner must actually no-op rather than fail.
if ! ./scripts/ci/test.sh meta >/dev/null 2>&1; then
  echo "❌ the meta tier must be a successful no-op when no TestHelper exists" >&2
  exit 1
fi
echo "  ✓ TestHelper NO verdict enforced; meta tier no-ops cleanly"

# Vendored IANA release + generated allowlist ------------------------------
bash ./scripts/validate/iana-source.sh

# Frozen C0 source release + projection ------------------------------------
bash ./scripts/validate/c0-release.sh

echo "✅ Dart core-utils identity, platform neutrality, seam boundary, frozen C0 projection, IANA provenance, workspace wiring, and TestHelper NO verdict conform"
