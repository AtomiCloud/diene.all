#!/usr/bin/env bash
set -euo pipefail

root_dir="$(git rev-parse --show-toplevel)"
cd "${root_dir}"

member_dir="packages/diene_dart_lib"
member_pubspec="${member_dir}/pubspec.yaml"

# Build a fixture that mirrors the repo-root layout the guard and bump.sh share:
# a VERSION file plus the member manifest at packages/diene_dart_lib/pubspec.yaml.
fixture="$(mktemp -d)"
trap 'rm -rf "${fixture}"' EXIT
mkdir -p "${fixture}/${member_dir}"
cp "${member_pubspec}" "${fixture}/${member_pubspec}"
cp VERSION "${fixture}/VERSION"
current_version="$(tr -d '[:space:]' <VERSION)"

# Positive: manifest + VERSION agree with the tag.
PACKAGE_ROOT="${fixture}" bash "${root_dir}/scripts/validate/publish-version.sh" "v${current_version}"

# Negative: a deliberate manifest/tag mismatch must be rejected.
yq -i '.version = "9.9.9"' "${fixture}/${member_pubspec}"
if PACKAGE_ROOT="${fixture}" bash "${root_dir}/scripts/validate/publish-version.sh" "v${current_version}"; then
  echo "❌ publish guard accepted a deliberate manifest/tag mismatch" >&2
  exit 1
fi

# bump.sh must stamp BOTH the root VERSION and the member pubspec.yaml.
cp "${member_pubspec}" "${fixture}/${member_pubspec}"
cp VERSION "${fixture}/VERSION"
PACKAGE_ROOT="${fixture}" bash "${root_dir}/scripts/release/bump.sh" v9.8.7
[[ $(yq -r '.version' "${fixture}/${member_pubspec}") != "9.8.7" ]] && echo "❌ release bump did not stamp member pubspec.yaml" >&2 && exit 1
[[ $(tr -d '[:space:]' <"${fixture}/VERSION") != "9.8.7" ]] && echo "❌ release bump did not stamp VERSION" >&2 && exit 1

# semantic-release must carry the member changelog and manifest as commit assets.
rg -q 'packages/diene_dart_lib/CHANGELOG.md' atomi_release.yaml || {
  echo "❌ packages/diene_dart_lib/CHANGELOG.md is absent from semantic-release assets" >&2
  exit 1
}
rg -q 'packages/diene_dart_lib/pubspec.yaml' atomi_release.yaml || {
  echo "❌ packages/diene_dart_lib/pubspec.yaml is absent from semantic-release assets" >&2
  exit 1
}

# The .gitlint conventional-commit vocabulary must match the release types.
release_types="$(yq -r '[.types[].type] | join(",")' atomi_release.yaml)"
gitlint_types="$(sed -n 's/^types = //p' .gitlint)"
[[ ${release_types} != "${gitlint_types}" ]] && echo "❌ .gitlint types do not match atomi_release.yaml" >&2 && exit 1

echo "✅ release stamping, manifest/tag positive + negative paths, assets, and gitlint vocabulary conform"
