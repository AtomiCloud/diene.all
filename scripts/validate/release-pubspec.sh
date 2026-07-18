#!/usr/bin/env bash
set -euo pipefail

root="$(pwd)"
fixture="$(mktemp -d)"
trap 'rm -rf "${fixture}"' EXIT
cp pubspec.yaml VERSION "${fixture}/"
(cd "${fixture}" && bash "${root}/scripts/release/bump.sh" v9.8.7)
[ "$(cat "${fixture}/VERSION")" != '9.8.7' ] && echo "❌ VERSION was not stamped" >&2 && exit 1
[ "$(yq '.version' "${fixture}/pubspec.yaml")" != '9.8.7+1' ] && echo "❌ pubspec.yaml was not stamped" >&2 && exit 1
rg -q 'pubspec.yaml' atomi_release.yaml || {
  echo "❌ pubspec.yaml is absent from release assets" >&2
  exit 1
}

echo "✅ release stamping updates VERSION and pubspec.yaml"
