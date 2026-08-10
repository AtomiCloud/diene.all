#!/usr/bin/env bash
set -euo pipefail

root_dir="$(git rev-parse --show-toplevel)"
cd "${root_dir}"

member_dir="packages/diene_core_utils"
member_pubspec="${member_dir}/pubspec.yaml"

# Build a fixture that mirrors the repo-root layout the guard and bump.sh share:
# a VERSION file plus the member manifest at packages/diene_core_utils/pubspec.yaml.
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

# The release config is registry-supplied `releaser` v2 (`schemaVersion: 2`): one
# document, no plugin list. The keys read below are `release.*`, not `plugins[]`.
release_config='release.yaml'
[[ ! -f ${release_config} ]] && echo "❌ ${release_config} does not exist" >&2 && exit 1
schema_version="$(yq -r '.schemaVersion // ""' "${release_config}")"
[[ ${schema_version} != "2" ]] && echo "❌ ${release_config} is not schemaVersion 2 (got '${schema_version}')" >&2 && exit 1

# `release.commit.assets` is ENFORCED by the releaser, not advisory: it aborts if a
# write lands outside the list. So every file this node's release writes must be in
# it — the member changelog the releaser writes, plus the two files bump.sh stamps.
assets="$(yq -r '.release.commit.assets[]? // ""' "${release_config}")"
[[ -z ${assets} ]] && echo "❌ ${release_config} declares no release.commit.assets" >&2 && exit 1
for required in \
  "${member_dir}/CHANGELOG.md" \
  "${member_pubspec}" \
  VERSION; do
  grep -Fxq "${required}" <<<"${assets}" || {
    echo "❌ ${required} is absent from release.commit.assets, so the release would abort when it is written" >&2
    exit 1
  }
done

# R-E33: the generated changelog must land BELOW the file's own heading. This is
# configuration, so it is asserted on printed VALUES instead of on a release run.
changelog_file="$(yq -r '.release.changelog.path // ""' "${release_config}")"
changelog_title="$(yq -r '.release.changelog.title // ""' "${release_config}")"
[[ -z ${changelog_file} ]] && echo "❌ ${release_config} declares no release.changelog.path" >&2 && exit 1
[[ ! -f ${changelog_file} ]] && echo "❌ changelog '${changelog_file}' does not exist" >&2 && exit 1
[[ -z ${changelog_title} ]] && echo "❌ ${release_config} declares no release.changelog.title, so every generated entry would be prepended ABOVE the changelog heading" >&2 && exit 1

# The title is reused only when the file literally starts with it, and is silently
# duplicated otherwise, so compare the exact leading bytes rather than eyeballing.
printf '%s' "${changelog_title}" >"${fixture}/changelog-title"
title_bytes="$(wc -c <"${fixture}/changelog-title")"
head -c "${title_bytes}" "${changelog_file}" >"${fixture}/changelog-head"
cmp -s "${fixture}/changelog-title" "${fixture}/changelog-head" || {
  echo "❌ the first ${title_bytes} bytes of ${changelog_file} are not the configured release.changelog.title" >&2
  exit 1
}

# This node versions a manifest, so `release.hooks.prepare` is NOT empty here: it
# must run bump.sh after the write, which is what stamps VERSION and the member
# pubspec asserted in the asset list above.
prepare_cmd="$(yq -r '[.release.hooks.prepare[]?.command] | join(" ; ")' "${release_config}")"
[[ ${prepare_cmd} != *"./scripts/release/bump.sh"* ]] && echo "❌ release.hooks.prepare does not run ./scripts/release/bump.sh, so no release would stamp the version" >&2 && exit 1
[[ ! -x scripts/release/bump.sh ]] && echo "❌ scripts/release/bump.sh is missing or not executable" >&2 && exit 1

# R-E33 second half: the member changelog is INSIDE prettier's scope in nix/fmt.nix
# (only the root Changelog.md is excluded), so an unformatted release entry reddens
# the format gate at the released commit. The formatter must run in the same hook.
[[ ${prepare_cmd} != *"./scripts/release/format-changelog.sh"* ]] && echo "❌ release.hooks.prepare does not run ./scripts/release/format-changelog.sh, so a release would commit unformatted changelog bytes" >&2 && exit 1
[[ ! -x scripts/release/format-changelog.sh ]] && echo "❌ scripts/release/format-changelog.sh is missing or not executable" >&2 && exit 1
prepare_phase="$(yq -r '[.release.hooks.prepare[]? | select(.command | test("bump[.]sh")) | .phase] | join(",")' "${release_config}")"
[[ ${prepare_phase} != "afterWrite" ]] && echo "❌ the bump.sh prepare hook runs at phase '${prepare_phase}', not afterWrite" >&2 && exit 1

# Commit linting reads this same file, so there is ONE vocabulary. A standalone
# .gitlint is retired and the semantic-release standard forbids re-adding it.
[[ -f .gitlint ]] && echo "❌ a standalone .gitlint exists; releaser lint-commit -c ${release_config} owns the vocabulary and the standard forbids that file" >&2 && exit 1
release_types="$(yq -r '[.types[].type] | join(",")' "${release_config}")"
[[ -z ${release_types} ]] && echo "❌ ${release_config} declares no commit types" >&2 && exit 1

echo "✅ changelog title agrees with ${changelog_file} over its first ${title_bytes} bytes; the afterWrite prepare hook stamps the version"
echo "✅ release stamping, manifest/tag positive + negative paths, schema-v2 assets, and the single commit vocabulary conform"
