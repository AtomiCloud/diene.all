#!/usr/bin/env bash
set -euo pipefail

# manifest==tag publish guard (R10/M1–M3).
#
# The release commit stamps VERSION and pubspec.yaml together (scripts/release/
# bump.sh). This guard verifies pubspec's version equals the VERSION file, and —
# when a tag argument is supplied (publish context) — that both equal the tag.
# The publish/CD path MUST run this before `dart pub publish`; a mismatch exits
# non-zero and blocks the publish.

manifest="$(yq -r '.version' pubspec.yaml)"
version_file="$(tr -d '[:space:]' <VERSION)"

[ -z "${manifest}" ] && echo "❌ pubspec.yaml has no version" >&2 && exit 1
[ -z "${version_file}" ] && echo "❌ VERSION is empty" >&2 && exit 1

if [ "${manifest}" != "${version_file}" ]; then
  echo "❌ manifest mismatch: pubspec.yaml=${manifest} VERSION=${version_file}" >&2
  exit 1
fi

tag="${1:-}"
if [ -n "${tag}" ]; then
  tag="${tag#v}"
  if [ "${manifest}" != "${tag}" ]; then
    echo "❌ manifest ${manifest} does not match tag ${tag}" >&2
    exit 1
  fi
  echo "✅ manifest ${manifest} == VERSION == tag ${tag}"
else
  echo "✅ manifest ${manifest} == VERSION ${version_file}"
fi
