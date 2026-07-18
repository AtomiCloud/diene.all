#!/usr/bin/env bash
set -euo pipefail

release_types="$(yq -r '.types[].type' atomi_release.yaml | sort)"
gitlint_types="$(sed -n -E 's/^types[[:space:]]*=[[:space:]]*//p' .gitlint | tr ',' '\n' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g' | sort)"

[ -z "${gitlint_types}" ] && echo "❌ .gitlint conventional-commit types are missing" >&2 && exit 1
[ "${release_types}" != "${gitlint_types}" ] && echo "❌ .gitlint types do not match atomi_release.yaml" >&2 && exit 1

echo "✅ .NET release and commit vocabularies match"
