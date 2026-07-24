#!/usr/bin/env bash
set -euo pipefail

# A positive allowlist, not a wildcard rejection: an unlisted grant is a new privilege.

committed="infra/root_chart/templates/rbac/role.yaml"
[ ! -f "${committed}" ] && echo "❌ operator RBAC: missing committed Role at ${committed}" >&2 && exit 1

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
coordination.k8s.io|leases|create
coordination.k8s.io|leases|get
coordination.k8s.io|leases|update
sample.diene.atomi.cloud|notes|get
sample.diene.atomi.cloud|notes|list
sample.diene.atomi.cloud|notes|update
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

echo "🔎 checking the committed manager Role against the least-privilege allowlist"

# shellcheck disable=SC2016 # yq expression, not shell — must stay single-quoted.
granted="$(yq -r '.rules[] | select(.resources != null) | .apiGroups[] as $g | .resources[] as $r | .verbs[] as $v | $g + "|" + $r + "|" + $v' "${committed}")"
while IFS= read -r triple; do
  [ -z "${triple}" ] && continue
  ! grep -qxF "${triple}" <<<"${allowed}" && echo "❌ operator RBAC: grant outside the least-privilege allowlist: ${triple}" >&2 && exit 1
done <<<"${granted}"

# The scraper identity owns /metrics, so the manager Role never needs a non-resource URL.
nonresource="$(yq -r '.rules[] | select(.nonResourceURLs != null) | .nonResourceURLs[]' "${committed}" || true)"
[ -n "${nonresource}" ] && echo "❌ operator RBAC: manager Role must not hold nonResourceURLs grants: ${nonresource}" >&2 && exit 1

echo "🧪 regenerating RBAC from the controller markers"

tmp="$(mktemp -d)"
trap 'rm -rf "${tmp}"' EXIT
controller-gen rbac:roleName=operator-template-manager \
  paths=./adapters/operator/controllers/... output:rbac:dir="${tmp}"

regenerated="$(diff -u "${committed}" "${tmp}/role.yaml" || true)"
[ -n "${regenerated}" ] && echo "${regenerated}" >&2 && echo "❌ operator RBAC: regenerated RBAC differs from committed ${committed} — run scripts/local/operator-manifests.sh" >&2 && exit 1

echo "✅ operator RBAC minimality passed"
