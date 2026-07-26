#!/usr/bin/env bash
set -euo pipefail

# Runs from the repo root. The publishable unit is the workspace member
# packages/diene_problems; the root pubspec is the non-published workspace shell.
root_dir="$(git rev-parse --show-toplevel)"
cd "${root_dir}"

member_dir="packages/diene_problems"
member_pubspec="${member_dir}/pubspec.yaml"

[[ -f ${member_pubspec} ]] || {
  echo "❌ member pubspec is missing: ${member_pubspec}" >&2
  exit 1
}

# Identity ------------------------------------------------------------------
[[ $(yq -r '.name' "${member_pubspec}") != "diene_problems" ]] && echo "❌ member pubspec name must be diene_problems" >&2 && exit 1
[[ $(yq -r '.version' "${member_pubspec}") != "$(cat VERSION)" ]] && echo "❌ member pubspec.yaml version and root VERSION must match" >&2 && exit 1
[[ $(yq -r '.repository' "${member_pubspec}") != "https://github.com/AtomiCloud/diene.dart_problems" ]] && echo "❌ member pubspec repository is not the snaked mirror" >&2 && exit 1

# Runtime dependency shape --------------------------------------------------
# The sample domain is self-contained (dart:convert only), so the published
# package carries ZERO runtime dependencies. This asserts the finalized shape;
# it is intentionally not hard-coded to any specific dependency name.
runtime_deps="$(yq -r '.dependencies // {} | length' "${member_pubspec}")"
[[ ${runtime_deps} -ne 0 ]] && echo "❌ diene_problems must have zero runtime dependencies (found ${runtime_deps})" >&2 && exit 1

# Workspace wiring ----------------------------------------------------------
if ! yq -r '.workspace[]' pubspec.yaml | grep -qx "packages/diene_problems"; then
  echo "❌ root pubspec.yaml .workspace must list packages/diene_problems" >&2
  exit 1
fi
[[ $(yq -r '.resolution' "${member_pubspec}") != "workspace" ]] && echo "❌ member pubspec must set resolution: workspace" >&2 && exit 1

# Required published artifacts ----------------------------------------------
for file in \
  "${member_dir}/lib/diene_problems.dart" \
  "${member_dir}/lib/test_helper.dart" \
  "${member_dir}/doc/diene_problems.md" \
  "${member_dir}/skills/diene-problems-usage/SKILL.md" \
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
