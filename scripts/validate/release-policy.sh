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

# semantic-release must carry the member changelog and manifest as commit assets.
#
# These are asserted STRUCTURALLY, by querying the specific plugin's fields,
# rather than by asking whether the strings appear somewhere in the file. A
# substring test is satisfied by a comment, by an unrelated plugin field, or by
# one correct path while the @semantic-release/git asset list omits the other —
# and the failure mode is a release that stamps a version but never commits the
# member manifest, with this gate reporting green.
echo '→ semantic-release asset structure'
changelog_file="$(yq -r '[.plugins[] | select(.module == "@semantic-release/changelog") | .config.changelogFile] | join(",")' atomi_release.yaml)"
printf '  changelog plugin changelogFile = %s\n' "${changelog_file}"
[[ ${changelog_file} == "${member_dir}/CHANGELOG.md" ]] || {
  echo "❌ @semantic-release/changelog must target exactly ${member_dir}/CHANGELOG.md, got '${changelog_file}'" >&2
  exit 1
}

git_assets="$(yq -r '[.plugins[] | select(.module == "@semantic-release/git") | .config.assets[]] | join(",")' atomi_release.yaml)"
git_asset_count="$(yq -r '[.plugins[] | select(.module == "@semantic-release/git") | .config.assets[]] | length' atomi_release.yaml)"
printf '  git plugin assets (%s) = %s\n' "${git_asset_count}" "${git_assets}"
expected_assets="${member_dir}/CHANGELOG.md,${member_dir}/pubspec.yaml,VERSION,docs/developer/CommitConventions.md"
[[ ${git_assets} == "${expected_assets}" ]] || {
  echo "❌ @semantic-release/git asset set must be exactly '${expected_assets}', got '${git_assets}'" >&2
  exit 1
}
[[ ${git_asset_count} -eq 4 ]] || {
  echo "❌ expected exactly 4 git commit assets, found ${git_asset_count}" >&2
  exit 1
}

# Negative fixtures: prove each structural assertion actually FAILS when the
# invariant is broken. Without this, "the query returned the right value" and
# "the query cannot tell the difference" look identical.
echo '→ negative fixtures for the asset structure'
assert_rejects() { # <label> <yq-mutation>
  local label="$1" mutation="$2" mutated="${fixture}/atomi_release.mutated.yaml"
  yq "${mutation}" atomi_release.yaml >"${mutated}"
  local got count
  got="$(yq -r '[.plugins[] | select(.module == "@semantic-release/git") | .config.assets[]] | join(",")' "${mutated}")"
  count="$(yq -r '[.plugins[] | select(.module == "@semantic-release/changelog") | .config.changelogFile] | join(",")' "${mutated}")"
  if [[ ${got} == "${expected_assets}" && ${count} == "${member_dir}/CHANGELOG.md" ]]; then
    echo "❌ negative fixture '${label}' did NOT change the asserted values; the gate cannot detect it" >&2
    exit 1
  fi
  printf '  rejected (correct): %s\n' "${label}"
}
assert_rejects 'member pubspec removed from git assets' \
  '(.plugins[] | select(.module == "@semantic-release/git") | .config.assets) |= map(select(. != "'"${member_dir}"'/pubspec.yaml"))'
assert_rejects 'member changelog removed from git assets' \
  '(.plugins[] | select(.module == "@semantic-release/git") | .config.assets) |= map(select(. != "'"${member_dir}"'/CHANGELOG.md"))'
# The decoy deliberately uses a NEUTRAL member name. Spelling the retired sample
# package here would plant its identifier back into the tree, which the R-E19a
# sweep correctly reads as surviving wrong-parent identity.
assert_rejects 'changelog plugin retargeted at a different member' \
  '(.plugins[] | select(.module == "@semantic-release/changelog") | .config.changelogFile) = "packages/some_other_member/CHANGELOG.md"'

# The .gitlint conventional-commit vocabulary must match the release types.
release_types="$(yq -r '[.types[].type] | join(",")' atomi_release.yaml)"
gitlint_types="$(sed -n 's/^types = //p' .gitlint)"
[[ ${release_types} != "${gitlint_types}" ]] && echo "❌ .gitlint types do not match atomi_release.yaml" >&2 && exit 1

echo "✅ release stamping, manifest/tag positive + negative paths, assets, and gitlint vocabulary conform"
