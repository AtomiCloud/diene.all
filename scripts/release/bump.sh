#!/usr/bin/env bash
set -euo pipefail

version="${1:-}"
[ -z "${version}" ] && echo "❌ version argument not set" >&2 && exit 1

printf '%s\n' "${version#v}" >VERSION
build_number="$(yq '.version' pubspec.yaml | sed -n 's/.*+\([0-9][0-9]*\)$/\1/p')"
build_number="${build_number:-1}"
sed -i -E "s/^version: .*/version: ${version#v}+${build_number}/" pubspec.yaml

echo "✅ VERSION and pubspec.yaml stamped to ${version#v}"
