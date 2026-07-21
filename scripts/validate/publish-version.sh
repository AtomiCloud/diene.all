#!/usr/bin/env bash
set -euo pipefail

root_dir="${PACKAGE_ROOT:-$(git rev-parse --show-toplevel)}"
tag="${1:-${GITHUB_REF_NAME:-}}"

[[ -z ${tag} ]] && echo "❌ provide a v*.*.* tag argument or GITHUB_REF_NAME" >&2 && exit 1
[[ ! ${tag} =~ ^v[0-9]+[.][0-9]+[.][0-9]+([+-][0-9A-Za-z.-]+)?$ ]] && echo "❌ tag must be a semantic v*.*.* version: ${tag}" >&2 && exit 1

expected="${tag#v}"
manifest_version="$(yq -r '.version' "${root_dir}/pubspec.yaml")"
version_file="$(tr -d '[:space:]' <"${root_dir}/VERSION")"

[[ ${manifest_version} != "${expected}" ]] && echo "❌ pubspec.yaml version (${manifest_version}) != tag version (${expected})" >&2 && exit 1
[[ ${version_file} != "${expected}" ]] && echo "❌ VERSION (${version_file}) != tag version (${expected})" >&2 && exit 1

echo "✅ pubspec.yaml and VERSION match ${tag}"
