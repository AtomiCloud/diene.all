#!/usr/bin/env bash
set -euo pipefail

# RBAC minimality gate: the committed manager Role must (a) carry no wildcard
# grant and (b) equal the Role regenerated from the controllers' rbac markers.

fail() {
  echo "❌ operator RBAC: $1" >&2
  exit 1
}

committed="infra/root_chart/templates/rbac/role.yaml"
[ -f "${committed}" ] || fail "missing committed Role at ${committed}"

# No wildcard apiGroups / resources / verbs.
if grep -nE "^[[:space:]]*-[[:space:]]*['\"]?\*['\"]?[[:space:]]*$" "${committed}"; then
  fail "wildcard grant found in ${committed}"
fi

tmp="$(mktemp -d)"
trap 'rm -rf "${tmp}"' EXIT
controller-gen rbac:roleName=operator-template-manager \
  paths=./adapters/operator/controllers/... output:rbac:dir="${tmp}"

if ! diff -u "${committed}" "${tmp}/role.yaml"; then
  fail "regenerated RBAC differs from committed ${committed} — run scripts/local/operator-manifests.sh"
fi

echo "✅ operator RBAC minimality passed"
