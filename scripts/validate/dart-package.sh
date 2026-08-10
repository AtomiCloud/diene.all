#!/usr/bin/env bash
set -euo pipefail

# Runs from the repository root. The publishable unit is the workspace member
# packages/diene_result; the root pubspec is the non-published workspace shell.
root_dir="$(git rev-parse --show-toplevel)"
cd "${root_dir}"

member_dir="packages/diene_result"
member_pubspec="${member_dir}/pubspec.yaml"

[[ -f ${member_pubspec} ]] || {
  echo "❌ member pubspec is missing: ${member_pubspec}" >&2
  exit 1
}

# Identity ------------------------------------------------------------------
[[ $(yq -r '.name' pubspec.yaml) != "diene_result_workspace" ]] && echo "❌ root pubspec name must be diene_result_workspace" >&2 && exit 1
[[ $(yq -r '.name' "${member_pubspec}") != "diene_result" ]] && echo "❌ member pubspec name must be diene_result" >&2 && exit 1
[[ $(yq -r '.version' "${member_pubspec}") != "$(tr -d '[:space:]' <VERSION)" ]] && echo "❌ member pubspec.yaml version and root VERSION must match" >&2 && exit 1
[[ $(yq -r '.repository' "${member_pubspec}") != "https://github.com/AtomiCloud/diene.dart_result" ]] && echo "❌ member pubspec repository is not the snaked mirror" >&2 && exit 1
[[ $(yq -r '.environment.sdk' "${member_pubspec}") != ">=3.12.0 <4.0.0" ]] && echo "❌ member Dart SDK constraint must be >=3.12.0 <4.0.0" >&2 && exit 1

# Canonical Problem dependency ---------------------------------------------
runtime_deps="$(yq -r '.dependencies // {} | length' "${member_pubspec}")"
[[ ${runtime_deps} -ne 1 ]] && echo "❌ diene_result must have exactly one runtime dependency (found ${runtime_deps})" >&2 && exit 1
[[ $(yq -r '.dependencies.diene_problems // ""' "${member_pubspec}") != "^0.1.0" ]] && echo "❌ diene_result must use the hosted diene_problems ^0.1.0 contract" >&2 && exit 1
if git ls-files --error-unmatch "${member_dir}/pubspec_overrides.yaml" >/dev/null 2>&1; then
  echo "❌ pubspec_overrides.yaml is local-only and must never be committed" >&2
  exit 1
fi
[[ -e ${member_dir}/lib/src/problem.dart ]] && echo "❌ diene_result must not define a competing Problem type" >&2 && exit 1
if rg -qi '^export .*problem' "${member_dir}/lib/diene_result.dart"; then
  echo "❌ diene_result must not re-export Problem" >&2
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
  "${member_dir}/lib/diene_result.dart" \
  "${member_dir}/lib/test_helper.dart" \
  "${member_dir}/doc/result.md" \
  "${member_dir}/skills/diene-result-usage/SKILL.md" \
  "${member_dir}/skills/diene-result-usage/patterns.md" \
  "${member_dir}/test/fixtures/c0/result-wire.json" \
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

echo "✅ Dart Result identity, canonical Problem edge, frozen C0 projection, workspace wiring, and TestHelper boundary conform"
