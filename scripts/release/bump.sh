#!/usr/bin/env bash
set -euo pipefail

version="${1:-}"
[[ -z ${version} ]] && echo "❌ version argument not set" >&2 && exit 1

# PACKAGE_ROOT mirrors the repo-root layout (VERSION + packages/diene_interfaces/
# pubspec.yaml) and is used by release-policy.sh's fixture round-trip. It matches
# publish-version.sh's path convention exactly.
root_dir="${PACKAGE_ROOT:-$(git rev-parse --show-toplevel)}"
version="${version#v}"

printf '%s\n' "${version}" >"${root_dir}/VERSION"
yq -i ".version = \"${version}\"" "${root_dir}/packages/diene_interfaces/pubspec.yaml"

echo "✅ VERSION and packages/diene_interfaces/pubspec.yaml stamped to ${version}"
