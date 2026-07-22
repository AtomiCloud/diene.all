#!/usr/bin/env bash
set -euo pipefail

mode="${1:-all}"
tmp="$(mktemp)"
trap 'rm -f "${tmp}"' EXIT

[ "${mode}" != "schema" ] && [ "${mode}" != "types" ] && [ "${mode}" != "all" ] && echo "❌ mode must be 'schema', 'types', or 'all'" >&2 && exit 1

yq -o=json atomi_release.yaml >"${tmp}"
if [ "${mode}" = "schema" ] || [ "${mode}" = "all" ]; then
  jq -e '
    .schemaVersion == 2 and
    .release.branches == ["main"] and
    .conventions.path == "docs/developer/CommitConventions.md" and
    .release.github == false and
    (.release.tagFormat | contains("${version}")) and
    ([.release.commit.message] | all(contains("[skip ci]") | not)) and
    (has("plugins") | not) and
    (has("gitlint") | not)
  ' "${tmp}" >/dev/null || {
    echo "❌ canonical releaser configuration is invalid" >&2
    exit 1
  }
fi

if [ "${mode}" = "types" ] || [ "${mode}" = "all" ]; then
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
  actual="$(jq -r '.types[].type' "${tmp}" | sort)"
  [ "${actual}" != "${expected}" ] && echo "❌ release types do not match the D3 vocabulary" >&2 && exit 1
fi

echo "✅ Release config ${mode} validation passed"
