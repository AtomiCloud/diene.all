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

# R-E33: the generated changelog must land BELOW the file's own heading, and the
# release must hand the git plugin formatter-clean bytes. Both are configuration,
# so they are asserted here on printed VALUES instead of on a release run.
changelog_file="$(yq -r '.plugins[] | select(.module == "@semantic-release/changelog") | .config.changelogFile // ""' atomi_release.yaml)"
changelog_title="$(yq -r '.plugins[] | select(.module == "@semantic-release/changelog") | .config.changelogTitle // ""' atomi_release.yaml)"
[[ -z ${changelog_file} ]] && echo "❌ the changelog plugin declares no changelogFile" >&2 && exit 1
[[ ! -f ${changelog_file} ]] && echo "❌ changelog '${changelog_file}' does not exist" >&2 && exit 1
[[ -z ${changelog_title} ]] && echo "❌ the changelog plugin declares no changelogTitle, so every generated entry would be prepended ABOVE the changelog heading" >&2 && exit 1

# @semantic-release/changelog reuses the title only when the file literally starts
# with it, and silently duplicates it otherwise, so compare the exact leading bytes.
printf '%s' "${changelog_title}" >"${fixture}/changelog-title"
title_bytes="$(wc -c <"${fixture}/changelog-title")"
head -c "${title_bytes}" "${changelog_file}" >"${fixture}/changelog-head"
cmp -s "${fixture}/changelog-title" "${fixture}/changelog-head" || {
  echo "❌ the first ${title_bytes} bytes of ${changelog_file} are not the configured changelogTitle" >&2
  exit 1
}

# The exec prepare step must format the generated entry before the git plugin
# commits it; the plugin chain runs exec after changelog and before git.
prepare_cmd="$(yq -r '.plugins[] | select(.module == "@semantic-release/exec") | .config.prepareCmd // ""' atomi_release.yaml)"
[[ ${prepare_cmd} != *"./scripts/release/format-changelog.sh"* ]] && echo "❌ the exec prepareCmd does not run ./scripts/release/format-changelog.sh" >&2 && exit 1
[[ ! -x scripts/release/format-changelog.sh ]] && echo "❌ scripts/release/format-changelog.sh is missing or not executable" >&2 && exit 1

# The .gitlint conventional-commit vocabulary must match the release types.
release_types="$(yq -r '[.types[].type] | join(",")' atomi_release.yaml)"
gitlint_types="$(sed -n 's/^types = //p' .gitlint)"
[[ ${release_types} != "${gitlint_types}" ]] && echo "❌ .gitlint types do not match atomi_release.yaml" >&2 && exit 1

echo "✅ changelog title agrees with ${changelog_file} over its first ${title_bytes} bytes; prepareCmd formats it before the git plugin commits"
echo "✅ release stamping, manifest/tag positive + negative paths, assets, and gitlint vocabulary conform"
