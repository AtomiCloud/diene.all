#!/usr/bin/env bash
set -euo pipefail

# Runs from the repository root. The publishable unit is the workspace member
# packages/diene_interfaces; the root pubspec is the non-published workspace
# shell.
root_dir="$(git rev-parse --show-toplevel)"
cd "${root_dir}"

member_dir="packages/diene_interfaces"
member_pubspec="${member_dir}/pubspec.yaml"

[[ -f ${member_pubspec} ]] || {
  echo "❌ member pubspec is missing: ${member_pubspec}" >&2
  exit 1
}

# Identity ------------------------------------------------------------------
[[ $(yq -r '.name' pubspec.yaml) != "diene_interfaces_workspace" ]] && echo "❌ root pubspec name must be diene_interfaces_workspace" >&2 && exit 1
[[ $(yq -r '.name' "${member_pubspec}") != "diene_interfaces" ]] && echo "❌ member pubspec name must be diene_interfaces" >&2 && exit 1
[[ $(yq -r '.version' "${member_pubspec}") != "$(tr -d '[:space:]' <VERSION)" ]] && echo "❌ member pubspec.yaml version and root VERSION must match" >&2 && exit 1
[[ $(yq -r '.repository' "${member_pubspec}") != "https://github.com/AtomiCloud/diene.dart_interfaces" ]] && echo "❌ member pubspec repository is not the snaked mirror" >&2 && exit 1
[[ $(yq -r '.environment.sdk' "${member_pubspec}") != ">=3.12.0 <4.0.0" ]] && echo "❌ member Dart SDK constraint must be >=3.12.0 <4.0.0" >&2 && exit 1

# Hosted family dependencies (R-E24: hosted deps, never a committed override) --
runtime_deps="$(yq -r '.dependencies // {} | length' "${member_pubspec}")"
[[ ${runtime_deps} -ne 2 ]] && echo "❌ diene_interfaces must have exactly two runtime dependencies (found ${runtime_deps})" >&2 && exit 1
[[ $(yq -r '.dependencies.diene_result // ""' "${member_pubspec}") != "^1.0.0" ]] && echo "❌ diene_interfaces must use the hosted diene_result ^1.0.0 contract" >&2 && exit 1
[[ $(yq -r '.dependencies.diene_problems // ""' "${member_pubspec}") != "^0.1.0" ]] && echo "❌ diene_interfaces must use the hosted diene_problems ^0.1.0 contract" >&2 && exit 1
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

# Seam boundary -------------------------------------------------------------
# This is the seam package: it owns contracts and fakes, never a concrete host
# implementation, and never a competing Problem or Result type.
if rg -n "^import 'dart:io'|package:flutter/|package:path/" "${member_dir}/lib"; then
  echo "❌ diene_interfaces must not depend on dart:io, Flutter, or package:path" >&2
  exit 1
fi
for forbidden in "${member_dir}/lib/src/problem.dart" "${member_dir}/lib/src/result.dart"; do
  [[ -e ${forbidden} ]] && echo "❌ diene_interfaces must not define a competing ${forbidden##*/} type" >&2 && exit 1
done
# RB-19: no trace seam, and no OTel implementer or exporter.
if rg -ni 'tracer|opentelemetry|package:opentelemetry' "${member_dir}/lib"; then
  echo "❌ diene_interfaces owns no trace seam and no OTel implementer (RB-19)" >&2
  exit 1
fi
# C0 §2: every type URI comes from the ONE builder, never a hand-formatted string.
if rg -n 'https?://[^ ]*/docs/' "${member_dir}/lib"; then
  echo "❌ problem type URIs must be minted by problemTypeUri, never hand-formatted (C0 §2)" >&2
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
  "${member_dir}/lib/diene_interfaces.dart" \
  "${member_dir}/lib/test_helper.dart" \
  "${member_dir}/doc/interfaces.md" \
  "${member_dir}/skills/diene-interfaces-usage/SKILL.md" \
  "${member_dir}/skills/diene-interfaces-usage/patterns.md" \
  "${member_dir}/test/fixtures/c0/problem-envelope.json" \
  "${member_dir}/test/fixtures/c0/SHA256SUMS" \
  "${member_dir}/tool/gen_c0_projection.dart" \
  "${member_dir}/LICENSE" \
  "${member_dir}/README.md" \
  "${member_dir}/CHANGELOG.md"; do
  [[ -f ${file} ]] || {
    echo "❌ required package artifact is missing: ${file}" >&2
    exit 1
  }
done

# TestHelper boundary -------------------------------------------------------
if rg -n 'package:(test|matcher|mockito|mocktail)/' "${member_dir}/lib/test_helper.dart"; then
  echo "❌ TestHelper must not depend on a test framework or mocking package" >&2
  exit 1
fi

# Frozen C0 source release + projection ------------------------------------
bash ./scripts/validate/c0-release.sh
(
  cd "${member_dir}"
  dart run tool/gen_c0_projection.dart --check
)

echo "✅ Dart interfaces identity, seam boundary, frozen C0 projection, workspace wiring, and TestHelper boundary conform"
