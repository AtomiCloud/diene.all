#!/usr/bin/env bash
set -euo pipefail

release_types="$(yq -r '.types[].type' atomi_release.yaml | sort | tr '\n' ',' | sed 's/,$//')"
gitlint_types="$(sed -n 's/^types = //p' .gitlint | tr ',' '\n' | sed 's/^ *//;s/ *$//' | sort | tr '\n' ',' | sed 's/,$//')"

[ "${release_types}" != "${gitlint_types}" ] && echo "❌ .gitlint types differ from atomi_release.yaml" >&2 && exit 1

echo "✅ Gitlint and release type vocabularies match"
