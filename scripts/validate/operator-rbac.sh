#!/usr/bin/env bash
set -euo pipefail

# RBAC minimality gate. Rather than only rejecting wildcards, this asserts a
# positive least-privilege allowlist: every granted group|resource|verb in the
# committed manager Role must appear in the allowlist below, the Role must hold no
# non-resource-URL grant (the scraper identity owns /metrics), and the Role must
# equal the markers' regenerated output.

fail() {
  echo "❌ operator RBAC: $1" >&2
  exit 1
}

committed="infra/root_chart/templates/rbac/role.yaml"
[ -f "${committed}" ] || fail "missing committed Role at ${committed}"

allowed="$(
  cat <<'EOF'
|configmaps|create
|configmaps|delete
|configmaps|get
|configmaps|list
|configmaps|patch
|configmaps|update
|configmaps|watch
|events|create
|events|patch
authentication.k8s.io|tokenreviews|create
authorization.k8s.io|subjectaccessreviews|create
sample.diene.atomi.cloud|notes|get
sample.diene.atomi.cloud|notes|list
sample.diene.atomi.cloud|notes|watch
sample.diene.atomi.cloud|journals|get
sample.diene.atomi.cloud|journals|list
sample.diene.atomi.cloud|journals|watch
sample.diene.atomi.cloud|notes/status|get
sample.diene.atomi.cloud|notes/status|patch
sample.diene.atomi.cloud|notes/status|update
sample.diene.atomi.cloud|journals/status|get
sample.diene.atomi.cloud|journals/status|patch
sample.diene.atomi.cloud|journals/status|update
sample.diene.atomi.cloud|notes/finalizers|update
EOF
)"

# shellcheck disable=SC2016 # yq expression, not shell — must stay single-quoted.
granted="$(yq -r '.rules[] | select(.resources != null) | .apiGroups[] as $g | .resources[] as $r | .verbs[] as $v | $g + "|" + $r + "|" + $v' "${committed}")"
while IFS= read -r triple; do
  [ -z "${triple}" ] && continue
  grep -qxF "${triple}" <<<"${allowed}" ||
    fail "grant outside the least-privilege allowlist: ${triple}"
done <<<"${granted}"

if yq -e '.rules[] | select(.nonResourceURLs != null)' "${committed}" >/dev/null 2>&1; then
  fail "manager Role must not hold nonResourceURLs grants (the scraper identity owns /metrics)"
fi

tmp="$(mktemp -d)"
trap 'rm -rf "${tmp}"' EXIT
controller-gen rbac:roleName=operator-template-manager \
  paths=./adapters/operator/controllers/... output:rbac:dir="${tmp}"
diff -u "${committed}" "${tmp}/role.yaml" ||
  fail "regenerated RBAC differs from committed ${committed} — run scripts/local/operator-manifests.sh"

echo "✅ operator RBAC minimality passed"
