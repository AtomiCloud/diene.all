#!/usr/bin/env bash
set -euo pipefail

root_dir="$(git rev-parse --show-toplevel)"
fixture="$(mktemp -d)"
trap 'rm -rf "${fixture}"' EXIT

cp pubspec.yaml VERSION "${fixture}/"
current_version="$(tr -d '[:space:]' <VERSION)"

PACKAGE_ROOT="${fixture}" bash "${root_dir}/scripts/validate/publish-version.sh" "v${current_version}"

yq -i '.version = "9.9.9"' "${fixture}/pubspec.yaml"
if PACKAGE_ROOT="${fixture}" bash "${root_dir}/scripts/validate/publish-version.sh" "v${current_version}"; then
  echo "❌ publish guard accepted a deliberate manifest/tag mismatch" >&2
  exit 1
fi

cp pubspec.yaml VERSION "${fixture}/"
PACKAGE_ROOT="${fixture}" bash "${root_dir}/scripts/release/bump.sh" v9.8.7
[[ $(yq -r '.version' "${fixture}/pubspec.yaml") != "9.8.7" ]] && echo "❌ release bump did not stamp pubspec.yaml" >&2 && exit 1
[[ $(tr -d '[:space:]' <"${fixture}/VERSION") != "9.8.7" ]] && echo "❌ release bump did not stamp VERSION" >&2 && exit 1

rg -q 'CHANGELOG.md' atomi_release.yaml || {
  echo "❌ CHANGELOG.md is absent from semantic-release assets" >&2
  exit 1
}
rg -q 'pubspec.yaml' atomi_release.yaml || {
  echo "❌ pubspec.yaml is absent from semantic-release assets" >&2
  exit 1
}

release_types="$(yq -r '[.types[].type] | join(",")' atomi_release.yaml)"
gitlint_types="$(sed -n 's/^types = //p' .gitlint)"
[[ ${release_types} != "${gitlint_types}" ]] && echo "❌ .gitlint types do not match atomi_release.yaml" >&2 && exit 1

echo "✅ release stamping and manifest/tag positive + negative paths conform"
