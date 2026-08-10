#!/usr/bin/env bash
set -euo pipefail

root_dir="$(git rev-parse --show-toplevel)"
cd "${root_dir}"

member_dir="packages/diene_api_engine"
member_pubspec="${member_dir}/pubspec.yaml"

# Build a fixture that mirrors the repo-root layout the guard and bump.sh share:
# a VERSION file plus the member manifest at packages/diene_api_engine/pubspec.yaml.
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

# The release must carry the member changelog and manifest as commit assets.
#
# SCHEMA v2. The parent renamed atomi_release.yaml to release.yaml and replaced the
# semantic-release plugin list with a `release:` block, so every lookup below reads
# the v2 key path. Asserting on the PARSED asset list rather than on a substring of
# the whole file: a bare `rg` over the file would also match the path where it
# appears in a comment or in `changelog.path`, so it could pass while the asset list
# itself was empty.
assets="$(yq -r '.release.commit.assets[]? // ""' release.yaml)"
for required in \
  'packages/diene_api_engine/CHANGELOG.md' \
  'packages/diene_api_engine/pubspec.yaml' \
  'VERSION'; do
  printf '%s\n' "${assets}" | grep -Fxq "${required}" || {
    echo "❌ ${required} is absent from release.commit.assets" >&2
    exit 1
  }
done

# R-E33: the generated changelog must land BELOW the file's own heading, and the
# release must hand the git plugin formatter-clean bytes. Both are configuration,
# so they are asserted here on printed VALUES instead of on a release run.
changelog_file="$(yq -r '.release.changelog.path // ""' release.yaml)"
changelog_title="$(yq -r '.release.changelog.title // ""' release.yaml)"
[[ -z ${changelog_file} ]] && echo "❌ release.changelog declares no path" >&2 && exit 1
[[ ! -f ${changelog_file} ]] && echo "❌ changelog '${changelog_file}' does not exist" >&2 && exit 1
[[ -z ${changelog_title} ]] && echo "❌ release.changelog declares no title, so every generated entry would be prepended ABOVE the changelog heading" >&2 && exit 1

# The changelog writer reuses the title only when the file literally starts with
# it, and silently duplicates it otherwise, so compare the exact leading bytes.
printf '%s' "${changelog_title}" >"${fixture}/changelog-title"
title_bytes="$(wc -c <"${fixture}/changelog-title")"
head -c "${title_bytes}" "${changelog_file}" >"${fixture}/changelog-head"
cmp -s "${fixture}/changelog-title" "${fixture}/changelog-head" || {
  echo "❌ the first ${title_bytes} bytes of ${changelog_file} are not the configured changelogTitle" >&2
  exit 1
}

# The prepare hooks must stamp the version and format the generated entry before
# the release commits its assets; v2 runs `release.hooks.prepare` after the
# changelog entry is written and before the commit is made.
prepare_cmd="$(yq -r '.release.hooks.prepare[]? // ""' release.yaml)"
[[ ${prepare_cmd} != *"./scripts/release/format-changelog.sh"* ]] && echo "❌ release.hooks.prepare does not run ./scripts/release/format-changelog.sh" >&2 && exit 1
[[ ${prepare_cmd} != *"./scripts/release/bump.sh"* ]] && echo "❌ release.hooks.prepare does not run ./scripts/release/bump.sh, so VERSION and the member manifest would never be stamped" >&2 && exit 1
[[ ! -x scripts/release/format-changelog.sh ]] && echo "❌ scripts/release/format-changelog.sh is missing or not executable" >&2 && exit 1

# The gitlint vocabulary comparison that stood here is RETIRED WITH ITS TOOL.
# `releaser lint-commit -c release.yaml` is now the commit-msg hook and reads the
# very same file this script validates, so the commit vocabulary and the release
# vocabulary cannot drift apart by construction — there is no second source left
# to disagree. The root `.gitlint` is an inherited orphan (the parent still tracks
# one too) and is deliberately not read here.

echo "✅ changelog title agrees with ${changelog_file} over its first ${title_bytes} bytes; prepare hooks stamp and format it before the release commits"
echo "✅ release stamping, manifest/tag positive + negative paths, and commit assets conform"
