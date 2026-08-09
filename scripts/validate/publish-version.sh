#!/usr/bin/env bash
set -euo pipefail

# PACKAGE_ROOT is a directory laid out like the repo root: it holds a VERSION
# file and the member manifest at packages/diene_dart_lib/pubspec.yaml. It
# defaults to the repo root and is overridden by release-policy.sh's fixture.
# bump.sh uses the SAME convention so the fixture round-trip stays consistent.
root_dir="${PACKAGE_ROOT:-$(git rev-parse --show-toplevel)}"
member_pubspec="${root_dir}/packages/diene_dart_lib/pubspec.yaml"
version_file="${root_dir}/VERSION"

tag="${1:-${GITHUB_REF_NAME:-}}"

[[ -z ${tag} ]] && echo "❌ provide a v*.*.* tag argument or GITHUB_REF_NAME" >&2 && exit 1
[[ ! ${tag} =~ ^v[0-9]+[.][0-9]+[.][0-9]+([+-][0-9A-Za-z.-]+)?$ ]] && echo "❌ tag must be a semantic v*.*.* version: ${tag}" >&2 && exit 1

expected="${tag#v}"
manifest_version="$(yq -r '.version' "${member_pubspec}")"
version_file_value="$(tr -d '[:space:]' <"${version_file}")"

[[ ${manifest_version} != "${expected}" ]] && echo "❌ member pubspec.yaml version (${manifest_version}) != tag version (${expected})" >&2 && exit 1
[[ ${version_file_value} != "${expected}" ]] && echo "❌ VERSION (${version_file_value}) != tag version (${expected})" >&2 && exit 1

echo "✅ member pubspec.yaml and VERSION match ${tag}"
