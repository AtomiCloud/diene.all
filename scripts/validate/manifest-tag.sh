#!/usr/bin/env bash
# Verifies pubspec.yaml AND VERSION match a supplied git tag
# (manifest==tag publish guard, R10/M1–M3; bun-lib pattern). Both the pubspec
# manifest version and the release VERSION stamp must equal the tag.
#
# Usage:
#   manifest-tag.sh <tag>        # e.g. v0.1.0 (leading `v` optional)
#
# Exits 1 on any mismatch (publish is blocked).
set -euo pipefail

tag="${1:-${GITHUB_REF_NAME:-}}"
[ -z "${tag}" ] && echo "❌ usage: manifest-tag.sh <tag> (e.g. v0.1.0)" >&2 && exit 1

tag_version="${tag#v}"
manifest_version="$(yq '.version' pubspec.yaml)"
version_file="$(tr -d '[:space:]' <VERSION)"

if [ "${manifest_version}" != "${tag_version}" ]; then
  echo "❌ pubspec version '${manifest_version}' != tag '${tag}'" >&2
  exit 1
fi
if [ "${version_file}" != "${tag_version}" ]; then
  echo "❌ VERSION '${version_file}' != tag '${tag}'" >&2
  exit 1
fi

echo "✅ manifest and VERSION match ${tag}"
