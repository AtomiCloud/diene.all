#!/usr/bin/env bash
set -euo pipefail

# Regenerate the operator's generated artifacts from the Go types + markers:
#   - deepcopy methods (api/v1alpha1/zz_generated.deepcopy.go)
#   - CRDs        -> infra/root_chart/templates/crds/*.yaml (plain chart resources)
#   - manager RBAC -> infra/root_chart/templates/rbac/role.yaml
# Generated artifacts are committed; the CRD-drift gate proves they stay in sync.

crd_dir="infra/root_chart/templates/crds"
rbac_dir="infra/root_chart/templates/rbac"
mkdir -p "${crd_dir}" "${rbac_dir}"

controller-gen object paths=./api/...
controller-gen crd paths=./api/... output:crd:dir="${crd_dir}"
controller-gen rbac:roleName=boron-manager \
  paths=./adapters/operator/controllers/... output:rbac:dir="${rbac_dir}"

echo "✅ operator manifests generated"
