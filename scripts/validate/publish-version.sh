#!/usr/bin/env bash
set -euo pipefail

tag="${1:-${GITHUB_REF_NAME:-}}"
[ -z "${tag}" ] && echo "❌ release tag not set" >&2 && exit 1

tag_version="${tag#v}"
manifest_version="$(yq '.version' pubspec.yaml)"
version_file="$(tr -d '[:space:]' <VERSION)"

[ "${manifest_version}" != "${tag_version}" ] && {
  echo "❌ pubspec version (${manifest_version}) != tag version (${tag_version})" >&2
  exit 1
}
[ "${version_file}" != "${tag_version}" ] && {
  echo "❌ VERSION (${version_file}) != tag version (${tag_version})" >&2
  exit 1
}

echo "✅ manifest and VERSION match ${tag}"
