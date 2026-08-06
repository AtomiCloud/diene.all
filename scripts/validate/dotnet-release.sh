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
merge
perf
refactor
style
test"
actual="$(yq -r '.types[].type' release.yaml | sort)"

[ "${actual}" != "${expected}" ] && echo "❌ releaser types do not match the .NET vocabulary" >&2 && exit 1
yq -e '.release.commit.assets[] | select(. == "App/App.csproj")' release.yaml >/dev/null || {
  echo "❌ release commit must include the stamped App/App.csproj" >&2
  exit 1
}

echo "✅ .NET releaser vocabulary and manifest asset are valid"
