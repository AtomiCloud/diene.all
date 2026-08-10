#!/usr/bin/env bash
set -euo pipefail

cluster_name="${K3D_CLUSTER_NAME:?set K3D_CLUSTER_NAME}"
registry_name="${K3D_REGISTRY_NAME:?set K3D_REGISTRY_NAME}"

if k3d cluster list --no-headers | awk '{print $1}' | rg -qx "${cluster_name}"; then
  k3d cluster delete "${cluster_name}"
else
  echo "✅ invocation-owned k3d cluster ${cluster_name} is already absent"
fi

if k3d registry list --no-headers | awk '{print $1}' | rg -qx "${registry_name}"; then
  k3d registry delete "${registry_name}"
fi

echo "✅ invocation-owned k3d cluster ${cluster_name} deleted"
