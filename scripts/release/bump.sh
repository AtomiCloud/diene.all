#!/usr/bin/env bash
set -euo pipefail

# Stamps the release version into VERSION and pubspec.yaml. A published Dart
# library uses a plain semver `version:` (no `+build` suffix — that is an
# app-only concern), so the pubspec version equals the tag exactly, which the
# manifest==tag guard (verify-manifest.sh) then enforces at publish time.

version="${1:-}"
[ -z "${version}" ] && echo "❌ version argument not set" >&2 && exit 1

printf '%s\n' "${version#v}" >VERSION
sed -i -E "s/^version: .*/version: ${version#v}/" pubspec.yaml

echo "✅ VERSION and pubspec.yaml stamped to ${version#v}"
