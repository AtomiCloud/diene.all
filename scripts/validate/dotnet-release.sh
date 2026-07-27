#!/usr/bin/env bash
set -euo pipefail

expected="amend
build
chore
ci
config
dep
docs
feat
fix
perf
refactor
style
test"
actual="$(yq -r '.types[].type' atomi_release.yaml | sort)"

[ "${actual}" != "${expected}" ] && echo "❌ releaser types do not match the .NET vocabulary" >&2 && exit 1
yq -e '.release.commit.assets[] | select(. == "VERSION")' atomi_release.yaml >/dev/null || {
  echo "❌ release commit must stamp VERSION" >&2
  exit 1
}

echo "✅ .NET releaser vocabulary and version asset are valid"
