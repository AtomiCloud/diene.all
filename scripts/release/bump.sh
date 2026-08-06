#!/usr/bin/env bash
set -euo pipefail

version="${1:-}"
[ -z "${version}" ] && echo "❌ version argument not set" >&2 && exit 1
[ "$(xmlstarlet select --template --value-of 'count(/Project/PropertyGroup/Version)' App/App.csproj)" != "1" ] && echo "❌ App/App.csproj must contain exactly one Version element" >&2 && exit 1

xmlstarlet ed --omit-decl --inplace \
  --update '/Project/PropertyGroup/Version' \
  --value "${version#v}" \
  App/App.csproj

echo "✅ App/App.csproj stamped to ${version#v}"
