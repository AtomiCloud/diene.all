#!/usr/bin/env bash
set -euo pipefail

# Stamp VERSION and pubspec.yaml to the next semantic-release version.
# A pub package version is plain semver (no `+build` metadata).

version="${1:-}"
[ -z "${version}" ] && echo "❌ version argument not set" >&2 && exit 1
version="${version#v}"

printf '%s\n' "${version}" >VERSION
sed -i -E "s/^version: .*/version: ${version}/" pubspec.yaml

echo "✅ VERSION and pubspec.yaml stamped to ${version}"
