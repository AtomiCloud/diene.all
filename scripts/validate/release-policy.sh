#!/usr/bin/env bash
set -euo pipefail

root_dir="$(git rev-parse --show-toplevel)"
cd "${root_dir}"

member_dir="packages/diene_e2e"
member_pubspec="${member_dir}/pubspec.yaml"

# Build a fixture that mirrors the repo-root layout the guard and bump.sh share:
# a VERSION file plus the member manifest at packages/diene_e2e/pubspec.yaml.
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

# The release config must carry the member changelog and manifest as commit assets.
#
# SCHEMA v2 THROUGHOUT. The parent renamed atomi_release.yaml to release.yaml AND
# replaced the semantic-release plugin list with native release.* keys, so every
# `.plugins[] | select(.module == ...)` query below would have returned null
# against the new file — and `// ""` would have turned each of those nulls into a
# clean empty string, i.e. an assertion that silently stops asserting. Neither
# side of the merge conflicted here, because both carried the same stale text.
rg -q 'packages/diene_e2e/CHANGELOG.md' release.yaml || {
  echo "❌ packages/diene_e2e/CHANGELOG.md is absent from release.commit.assets" >&2
  exit 1
}
rg -q 'packages/diene_e2e/pubspec.yaml' release.yaml || {
  echo "❌ packages/diene_e2e/pubspec.yaml is absent from release.commit.assets" >&2
  exit 1
}

# R-E33: the generated changelog must land BELOW the file's own heading, and the
# release must hand the commit step formatter-clean bytes. Both are configuration,
# so they are asserted here on printed VALUES instead of on a release run.
changelog_file="$(yq -r '.release.changelog.path // ""' release.yaml)"
changelog_title="$(yq -r '.release.changelog.title // ""' release.yaml)"
[[ -z ${changelog_file} ]] && echo "❌ release.changelog.path is not declared" >&2 && exit 1
[[ ! -f ${changelog_file} ]] && echo "❌ changelog '${changelog_file}' does not exist" >&2 && exit 1
[[ -z ${changelog_title} ]] && echo "❌ release.changelog.title is not declared, so every generated entry would be prepended ABOVE the changelog heading" >&2 && exit 1

# @semantic-release/changelog reuses the title only when the file literally starts
# with it, and silently duplicates it otherwise, so compare the exact leading bytes.
printf '%s' "${changelog_title}" >"${fixture}/changelog-title"
title_bytes="$(wc -c <"${fixture}/changelog-title")"
head -c "${title_bytes}" "${changelog_file}" >"${fixture}/changelog-head"
cmp -s "${fixture}/changelog-title" "${fixture}/changelog-head" || {
  echo "❌ the first ${title_bytes} bytes of ${changelog_file} are not the configured changelogTitle" >&2
  exit 1
}

# The prepare hooks must format the generated entry before the commit step runs;
# release.hooks.prepare executes after the changelog is written and before assets
# are committed. Asserted as a joined list because the v2 schema takes an ordered
# sequence of commands where the v1 schema took one `prepareCmd` string.
prepare_cmd="$(yq -r '[.release.hooks.prepare // [] | .[]] | join(" && ")' release.yaml)"
[[ ${prepare_cmd} != *"./scripts/release/format-changelog.sh"* ]] && echo "❌ release.hooks.prepare does not run ./scripts/release/format-changelog.sh" >&2 && exit 1
[[ ${prepare_cmd} != *"./scripts/release/bump.sh"* ]] && echo "❌ release.hooks.prepare does not run ./scripts/release/bump.sh, so VERSION and the member pubspec would be committed unstamped" >&2 && exit 1
[[ ! -x scripts/release/format-changelog.sh ]] && echo "❌ scripts/release/format-changelog.sh is missing or not executable" >&2 && exit 1

# The commit-message vocabulary must come from release.yaml and nowhere else.
# gitlint is RETIRED on this node: the binary is gone from nix/packages.nix and
# nix/env.nix, `releaser lint-commit -c release.yaml` owns commit-message
# validation via the a-releaser-commit hook, and docs/standards/semantic-release
# states there is no standalone .gitlint file and one must not be added. The old
# assertion compared release types against `.gitlint`; keeping it would have been
# a check against a file the merge deletes. It is replaced — not dropped — by an
# assertion that the retirement actually holds, so a reintroduced .gitlint is
# caught rather than silently tolerated.
release_types="$(yq -r '[.types[].type] | join(",")' release.yaml)"
[[ -z ${release_types} ]] && echo "❌ release.yaml declares no commit types" >&2 && exit 1
[[ -e .gitlint ]] && echo "❌ .gitlint exists; release.yaml is the only commit vocabulary and gitlint is retired" >&2 && exit 1

echo "✅ changelog title agrees with ${changelog_file} over its first ${title_bytes} bytes; prepare hooks format it before the commit step"
echo "✅ release stamping, manifest/tag positive + negative paths, assets, and the single-source commit vocabulary (${release_types}) conform"
