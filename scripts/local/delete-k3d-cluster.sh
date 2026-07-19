#!/usr/bin/env bash
set -euo pipefail

# Sandbox isolation (RB-66): resolve the same path-keyed cluster/registry the
# matching create step used so teardown only ever targets this sandbox.
_here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${_here}/k3d-isolation.sh"

cluster_name="${K3D_CLUSTER_NAME}"
registry_name="${K3D_REGISTRY_NAME}"

if k3d cluster list --no-headers | awk '{print $1}' | rg -qx "${cluster_name}"; then
  k3d cluster delete "${cluster_name}"
else
  echo "✅ k3d cluster ${cluster_name} is already absent"
fi

if k3d registry list --no-headers | awk '{print $1}' | rg -qx "${registry_name}"; then
  k3d registry delete "${registry_name}"
fi

echo "✅ k3d cluster ${cluster_name} deleted"
