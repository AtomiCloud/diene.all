#!/usr/bin/env bash
set -euo pipefail

mode="${1:-all}"
tmp="$(mktemp)"
trap 'rm -f "${tmp}"' EXIT

[ "${mode}" != "schema" ] && [ "${mode}" != "types" ] && [ "${mode}" != "all" ] && echo "❌ mode must be 'schema', 'types', or 'all'" >&2 && exit 1

yq -o=json atomi_release.yaml >"${tmp}"
if [ "${mode}" = "schema" ] || [ "${mode}" = "all" ]; then
  jq -e '.branches == ["main"]' "${tmp}" >/dev/null || {
    echo "❌ release branches must be exactly [main]" >&2
    exit 1
  }
  jq -e '.conventionMarkdown.path == "docs/developer/CommitConventions.md"' "${tmp}" >/dev/null || {
    echo "❌ conventionMarkdown path is invalid" >&2
    exit 1
  }
  jq -e 'has("gitlint") | not' "${tmp}" >/dev/null || {
    echo "❌ standalone gitlint configuration is forbidden" >&2
    exit 1
  }
  modules="$(jq -r '.plugins[].module' "${tmp}" | paste -sd, -)"
  [ "${modules}" != "@semantic-release/changelog,@semantic-release/exec,@semantic-release/git,@semantic-release/github" ] && echo "❌ base release plugin chain is invalid: ${modules}" >&2 && exit 1
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
