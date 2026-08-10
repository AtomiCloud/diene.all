#!/usr/bin/env bash
set -euo pipefail

root_dir="$(git rev-parse --show-toplevel)"
cd "${root_dir}"

member_dir="packages/diene_config"
member_pubspec="${member_dir}/pubspec.yaml"

# Build a fixture that mirrors the repo-root layout the guard and bump.sh share:
# a VERSION file plus the member manifest at packages/diene_config/pubspec.yaml.
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
# SCHEMA v2. The parent renamed atomi_release.yaml to release.yaml and replaced
# the semantic-release plugin list with releaser's own `release:` block. Every
# assertion below is the same assertion as before, re-pointed at the key that now
# holds the value: changelogFile -> .release.changelog.path, changelogTitle ->
# .release.changelog.title, the git plugin's assets -> .release.commit.assets,
# and exec's prepareCmd -> .release.hooks.prepare[].command.
#
# These are asserted STRUCTURALLY, by querying the specific key, rather than by
# asking whether the strings appear somewhere in the file. A substring test is
# satisfied by a comment, by an unrelated field, or by one correct path while the
# asset list omits the other — and the failure mode is a release that stamps a
# version but never commits the member manifest, with this gate reporting green.
echo '→ release asset structure'
changelog_file="$(yq -r '.release.changelog.path // ""' release.yaml)"
printf '  release.changelog.path = %s\n' "${changelog_file}"
[[ ${changelog_file} == "${member_dir}/CHANGELOG.md" ]] || {
  echo "❌ release.changelog.path must be exactly ${member_dir}/CHANGELOG.md, got '${changelog_file}'" >&2
  exit 1
}

git_assets="$(yq -r '[.release.commit.assets[]] | join(",")' release.yaml)"
git_asset_count="$(yq -r '[.release.commit.assets[]] | length' release.yaml)"
printf '  release.commit.assets (%s) = %s\n' "${git_asset_count}" "${git_assets}"
expected_assets="${member_dir}/CHANGELOG.md,${member_dir}/pubspec.yaml,VERSION,docs/developer/CommitConventions.md"
[[ ${git_assets} == "${expected_assets}" ]] || {
  echo "❌ release.commit.assets must be exactly '${expected_assets}', got '${git_assets}'" >&2
  exit 1
}
[[ ${git_asset_count} -eq 4 ]] || {
  echo "❌ expected exactly 4 commit assets, found ${git_asset_count}" >&2
  exit 1
}

# Negative fixtures: prove each structural assertion actually FAILS when the
# invariant is broken. Without this, "the query returned the right value" and
# "the query cannot tell the difference" look identical.
echo '→ negative fixtures for the asset structure'
assert_rejects() { # <label> <yq-mutation>
  local label="$1" mutation="$2" mutated="${fixture}/release.mutated.yaml"
  yq "${mutation}" release.yaml >"${mutated}"
  local got count
  got="$(yq -r '[.release.commit.assets[]] | join(",")' "${mutated}")"
  count="$(yq -r '.release.changelog.path // ""' "${mutated}")"
  if [[ ${got} == "${expected_assets}" && ${count} == "${member_dir}/CHANGELOG.md" ]]; then
    echo "❌ negative fixture '${label}' did NOT change the asserted values; the gate cannot detect it" >&2
    exit 1
  fi
  printf '  rejected (correct): %s\n' "${label}"
}
assert_rejects 'member pubspec removed from commit assets' \
  '.release.commit.assets |= map(select(. != "'"${member_dir}"'/pubspec.yaml"))'
assert_rejects 'member changelog removed from commit assets' \
  '.release.commit.assets |= map(select(. != "'"${member_dir}"'/CHANGELOG.md"))'
# The decoy deliberately uses a NEUTRAL member name. Spelling the retired sample
# package here would plant its identifier back into the tree, which the R-E19a
# sweep correctly reads as surviving wrong-parent identity.
assert_rejects 'changelog retargeted at a different member' \
  '.release.changelog.path = "packages/some_other_member/CHANGELOG.md"'

# R-E33: the generated changelog must land BELOW the file's own heading, and the
# release must be handed formatter-clean bytes. Both are configuration, so they
# are asserted here on printed VALUES instead of on a release run.
changelog_title="$(yq -r '.release.changelog.title // ""' release.yaml)"
[[ -z ${changelog_file} ]] && echo "❌ release.yaml declares no release.changelog.path" >&2 && exit 1
[[ ! -f ${changelog_file} ]] && echo "❌ changelog '${changelog_file}' does not exist" >&2 && exit 1
[[ -z ${changelog_title} ]] && echo "❌ release.yaml declares no release.changelog.title, so every generated entry would be prepended ABOVE the changelog heading" >&2 && exit 1

# The writer reuses the title only when the file literally starts with it, and
# silently duplicates it otherwise, so compare the exact leading bytes.
printf '%s' "${changelog_title}" >"${fixture}/changelog-title"
title_bytes="$(wc -c <"${fixture}/changelog-title")"
head -c "${title_bytes}" "${changelog_file}" >"${fixture}/changelog-head"
cmp -s "${fixture}/changelog-title" "${fixture}/changelog-head" || {
  echo "❌ the first ${title_bytes} bytes of ${changelog_file} are not the configured release.changelog.title" >&2
  exit 1
}

# The prepare hook must format the generated entry before the assets are staged;
# releaser runs the afterWrite phase after the changelog is written.
prepare_cmd="$(yq -r '[.release.hooks.prepare[].command] | join(" ; ")' release.yaml)"
[[ ${prepare_cmd} != *"./scripts/release/format-changelog.sh"* ]] && echo "❌ no release.hooks.prepare command runs ./scripts/release/format-changelog.sh" >&2 && exit 1
[[ ${prepare_cmd} != *"./scripts/release/bump.sh"* ]] && echo "❌ no release.hooks.prepare command runs ./scripts/release/bump.sh" >&2 && exit 1
[[ ! -x scripts/release/format-changelog.sh ]] && echo "❌ scripts/release/format-changelog.sh is missing or not executable" >&2 && exit 1

# The .gitlint vocabulary coupling was RETIRED WITH gitlint, not dropped silently.
# gitlint is gone from nix/env.nix and nix/packages.nix, `a-releaser-commit` now
# runs `releaser lint-commit -c release.yaml`, and docs/standards/semantic-release
# states there is no standalone .gitlint file. There is now ONE vocabulary — the
# one in this file — so there is no second list left to agree with. The generated
# docs/developer/CommitConventions.md is checked against it by `releaser
# conventions` and by .ratchet-ops/handoffs/check-doc-vs-release-yaml.sh, not here.

echo "✅ changelog title agrees with ${changelog_file} over its first ${title_bytes} bytes; the prepare hook formats it before the assets are staged"
echo "✅ release stamping, manifest/tag positive + negative paths, and commit assets conform"
