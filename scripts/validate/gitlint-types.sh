#!/usr/bin/env bash
set -euo pipefail

release_types="$(yq -r '.types[].type' atomi_release.yaml | sort | tr '\n' ',' | sed 's/,$//')"
gitlint_types="$(sed -n 's/^[[:space:]]*types[[:space:]]*=[[:space:]]*//p' .gitlint | tr ',' '\n' | sed 's/^ *//;s/ *$//' | sort | tr '\n' ',' | sed 's/,$//')"

[ -z "${release_types}" ] && echo "❌ no release types parsed from atomi_release.yaml" >&2 && exit 1
[ -z "${gitlint_types}" ] && echo "❌ no gitlint types parsed from .gitlint" >&2 && exit 1
tr ',' '\n' <<<"${release_types}" | rg -qx dep || {
  echo "❌ release types must contain dep" >&2
  exit 1
}
[ "${release_types}" != "${gitlint_types}" ] && echo "❌ .gitlint types differ from atomi_release.yaml" >&2 && exit 1

echo "✅ Gitlint and release type vocabularies match"
