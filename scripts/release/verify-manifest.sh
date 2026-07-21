#!/usr/bin/env bash
set -euo pipefail

# Manifest==tag publish guard (R10/M1–M3). Run immediately before
# `dart pub publish` on a tagged release: it verifies the pubspec `version:`
# matches both the stamped VERSION file and the release tag, and EXITS 1 on any
# mismatch so a drifted manifest can never be published.
#
# Usage: verify-manifest.sh <tag>
#   <tag> may carry a leading 'v' (e.g. v1.2.3); it is stripped for comparison.

tag="${1:-}"
[ -z "${tag}" ] && echo "❌ tag argument not set" >&2 && exit 1
tag="${tag#v}"

manifest="$(yq '.version' pubspec.yaml)"
file="$(tr -d '[:space:]' <VERSION)"

if [ "${manifest}" != "${file}" ]; then
  echo "❌ manifest drift: pubspec.yaml version '${manifest}' != VERSION '${file}'" >&2
  exit 1
fi
if [ "${manifest}" != "${tag}" ]; then
  echo "❌ manifest==tag mismatch: pubspec.yaml version '${manifest}' != tag '${tag}'" >&2
  exit 1
fi

echo "✅ manifest matches tag ${tag}"
