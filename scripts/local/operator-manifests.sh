#!/usr/bin/env bash
set -euo pipefail

# Regenerate the operator's generated artifacts from the Go types + markers:
#   - deepcopy methods (api/*/v1alpha1/zz_generated.deepcopy.go)
#   - CRDs        -> infra/root_chart/templates/crds/*.yaml (plain chart resources)
#   - manager RBAC -> infra/root_chart/templates/rbac/role.yaml
# Generated artifacts are committed; the CRD-drift gate proves they stay in sync.

crd_dir="infra/root_chart/templates/crds"
rbac_dir="infra/root_chart/templates/rbac"
mkdir -p "${crd_dir}" "${rbac_dir}"

controller-gen object paths=./api/...
controller-gen crd paths=./api/... output:crd:dir="${crd_dir}"
rbac_tmp="$(mktemp -d)"
cleanup() {
  rm -rf -- "${rbac_tmp}"
}
trap cleanup EXIT

controller-gen rbac:roleName=fleet-operator-manager \
  paths=./adapters/operator/controllers/... output:rbac:dir="${rbac_tmp}"

if [[ -f "${rbac_tmp}/role.yaml" ]]; then
  cp "${rbac_tmp}/role.yaml" "${rbac_dir}/role.yaml"
else
  # controller-gen emits no RBAC file when the package has zero markers, but
  # the chart's ClusterRoleBinding requires the manager ClusterRole to exist.
  cat >"${rbac_dir}/role.yaml" <<'EOF'
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: fleet-operator-manager
rules: []
EOF
fi

echo "✅ operator manifests generated"
