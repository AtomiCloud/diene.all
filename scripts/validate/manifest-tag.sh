#!/usr/bin/env bash
# Verifies the pubspec manifest version matches a supplied git tag
# (manifest==tag publish guard, R10/M1–M3; bun-lib pattern).
#
# Usage:
#   manifest-tag.sh <tag>        # check pubspec.yaml#version == <tag>
#
# <tag> may include a leading `v`. Exits 1 on mismatch (publish is blocked).
set -euo pipefail

tag="${1:?usage: manifest-tag.sh <tag> (e.g. v0.1.0)}"
version="$(yq '.version' pubspec.yaml)"
manifest="${tag#v}"

if [ "${version}" != "${manifest}" ]; then
  echo "❌ manifest version '${version}' != tag '${tag}'" >&2
  exit 1
fi

echo "✅ manifest version ${version} == tag ${tag}"
