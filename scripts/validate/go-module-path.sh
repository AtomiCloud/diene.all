#!/usr/bin/env bash
set -euo pipefail

expected_module="$(yq -r '.module' .config/go-lib.yaml)"
expected_proxy_module="$(yq -r '.proxyModule' .config/go-lib.yaml)"
expected_mirror="$(yq -r '.mirror' .config/go-lib.yaml)"
actual_module="$(go list -m -f '{{.Path}}' "${expected_module}")"

[ "${actual_module}" != "${expected_module}" ] && echo "❌ module path '${actual_module}' must be '${expected_module}'" >&2 && exit 1
[ "${expected_module}" != "github.com/${expected_mirror}" ] && echo "❌ module path and mirror identity disagree" >&2 && exit 1
[ "${expected_proxy_module}" != "github.com/!atomi!cloud/${expected_mirror#AtomiCloud/}" ] && echo "❌ escaped proxy path and mirror identity disagree" >&2 && exit 1
rg -F "${expected_module}" README.md docs/developer/go-lib-baseline.md >/dev/null || {
  echo "❌ module identity is missing from library documentation" >&2
  exit 1
}

echo "✅ Go module path matches the mirror identity"
