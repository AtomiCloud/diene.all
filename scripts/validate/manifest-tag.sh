#!/usr/bin/env bash
set -euo pipefail

tag="${1:-${GITHUB_REF_NAME:-}}"
[ -z "${tag}" ] && echo "❌ release tag argument not set" >&2 && exit 64

tag="${tag#refs/tags/}"
tag="${tag#v}"
manifest="$(yq '.version' pubspec.yaml)"

if [ "${manifest}" != "${tag}" ]; then
  echo "❌ pubspec version ${manifest} does not match tag ${tag}" >&2
  exit 1
fi

echo "✅ pubspec version ${manifest} matches tag ${tag}"
