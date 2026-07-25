#!/usr/bin/env bash
set -euo pipefail

# A positive allowlist, not a wildcard rejection: an unlisted grant is a new privilege.

committed="infra/root_chart/templates/rbac/role.yaml"
[ ! -f "${committed}" ] && echo "❌ operator RBAC: missing committed Role at ${committed}" >&2 && exit 1

allowed="$(
  cat <<'EOF'
|events|create
|events|patch
|secrets|get
|secrets|list
|secrets|watch
|services|get
|services|list
|services|watch
apps|deployments|create
apps|deployments|delete
apps|deployments|get
apps|deployments|list
apps|deployments|patch
apps|deployments|update
apps|deployments|watch
authentication.k8s.io|tokenreviews|create
authorization.k8s.io|subjectaccessreviews|create
coordination.k8s.io|leases|create
coordination.k8s.io|leases|get
coordination.k8s.io|leases|update
boron.atomi.cloud|accounts|get
boron.atomi.cloud|accounts|list
boron.atomi.cloud|accounts|update
boron.atomi.cloud|accounts|watch
boron.atomi.cloud|accounts/status|get
boron.atomi.cloud|accounts/status|patch
boron.atomi.cloud|accounts/status|update
boron.atomi.cloud|tunnels|get
boron.atomi.cloud|tunnels|list
boron.atomi.cloud|tunnels|update
boron.atomi.cloud|tunnels|watch
boron.atomi.cloud|tunnels/status|get
boron.atomi.cloud|tunnels/status|patch
boron.atomi.cloud|tunnels/status|update
boron.atomi.cloud|tunnels/finalizers|update
boron.atomi.cloud|exposures|get
boron.atomi.cloud|exposures|list
boron.atomi.cloud|exposures|update
boron.atomi.cloud|exposures|watch
boron.atomi.cloud|exposures/status|get
boron.atomi.cloud|exposures/status|patch
boron.atomi.cloud|exposures/status|update
boron.atomi.cloud|exposures/finalizers|update
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
controller-gen rbac:roleName=boron-manager \
  paths=./adapters/operator/controllers/... output:rbac:dir="${tmp}"

regenerated="$(diff -u "${committed}" "${tmp}/role.yaml" || true)"
[ -n "${regenerated}" ] && echo "${regenerated}" >&2 && echo "❌ operator RBAC: regenerated RBAC differs from committed ${committed} — run scripts/local/operator-manifests.sh" >&2 && exit 1

echo "✅ operator RBAC minimality passed"
