#!/usr/bin/env bash
set -euo pipefail

version="${1:-}"
[[ -z ${version} ]] && echo "❌ version argument not set" >&2 && exit 1

root_dir="${PACKAGE_ROOT:-$(git rev-parse --show-toplevel)}"
version="${version#v}"

printf '%s\n' "${version}" >"${root_dir}/VERSION"
yq -i ".version = \"${version}\"" "${root_dir}/pubspec.yaml"

echo "✅ VERSION and pubspec.yaml stamped to ${version}"
