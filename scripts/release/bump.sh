#!/usr/bin/env bash
set -euo pipefail

version="${1:-}"
[ -z "${version}" ] && echo "❌ version argument not set" >&2 && exit 1

# Library package: stamp a plain semver `version:` (no +build; that is a mobile
# app concern). VERSION and pubspec.yaml are stamped identically so the
# manifest==tag guard holds.
printf '%s\n' "${version#v}" >VERSION
sed -i -E "s/^version: .*/version: ${version#v}/" pubspec.yaml

echo "✅ VERSION and pubspec.yaml stamped to ${version#v}"
