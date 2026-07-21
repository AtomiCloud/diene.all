#!/usr/bin/env bash
# Stamps the release version into VERSION and pubspec.yaml.
#
# Dart library packages publish a plain semver version (no store build number),
# so the pubspec `version` is stamped as `<version>` (semantic-release prepare
# step). The manifest==tag publish guard (scripts/validate/manifest-tag.sh)
# verifies the result matches the git tag at publish time.
set -euo pipefail

version="${1:-}"
[ -z "${version}" ] && echo "❌ version argument not set" >&2 && exit 1

printf '%s\n' "${version#v}" >VERSION
sed -i -E "s/^version: .*/version: ${version#v}/" pubspec.yaml

echo "✅ VERSION and pubspec.yaml stamped to ${version#v}"
