#!/usr/bin/env bash
set -euo pipefail

root="$(pwd)"
fixture="$(mktemp -d)"
trap 'rm -rf "${fixture}"' EXIT
cp pubspec.yaml VERSION "${fixture}/"
(cd "${fixture}" && bash "${root}/scripts/release/bump.sh" v9.8.7)
[ "$(tr -d '[:space:]' <"${fixture}/VERSION")" != '9.8.7' ] && {
  echo "❌ VERSION was not stamped" >&2
  exit 1
}
[ "$(yq '.version' "${fixture}/pubspec.yaml")" != '9.8.7' ] && {
  echo "❌ pubspec.yaml was not stamped" >&2
  exit 1
}
rg -q 'pubspec.yaml' atomi_release.yaml || {
  echo "❌ pubspec.yaml is absent from release assets" >&2
  exit 1
}
[ ! -f CHANGELOG.md ] && {
  echo "❌ canonical CHANGELOG.md is absent" >&2
  exit 1
}
rg -q 'changelogFile: CHANGELOG[.]md' atomi_release.yaml || {
  echo "❌ semantic-release does not target canonical CHANGELOG.md" >&2
  exit 1
}
if rg -q '^CHANGELOG[.]md$' .pubignore; then
  echo "❌ canonical CHANGELOG.md is excluded from the pub archive" >&2
  exit 1
fi

echo "✅ release stamping and canonical changelog wiring passed"
