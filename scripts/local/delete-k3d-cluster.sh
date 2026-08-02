#!/usr/bin/env bash
set -euo pipefail

cluster_name="${K3D_CLUSTER_NAME:-diene-helm-wrapper}"
registry_name="${K3D_REGISTRY_NAME:-diene-wrapper-registry}"

clusters="$(k3d cluster list --no-headers | awk '{print $1}')"
if printf '%s\n' "${clusters}" | rg -qx "${cluster_name}"; then
  k3d cluster delete "${cluster_name}"
else
  echo "✅ k3d cluster ${cluster_name} is already absent"
fi

registries="$(k3d registry list --no-headers | awk '{print $1}')"
if printf '%s\n' "${registries}" | rg -qx "${registry_name}"; then
  k3d registry delete "${registry_name}"
fi

echo "✅ k3d cluster ${cluster_name} deleted"
