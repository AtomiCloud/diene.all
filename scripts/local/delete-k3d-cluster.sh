#!/usr/bin/env bash
set -euo pipefail

path_key="$(printf '%s' "${PWD}" | sha256sum | cut -c1-8)"
cluster_name="${K3D_CLUSTER_NAME:-diene-aluminium-${path_key}}"
registry_name="${K3D_REGISTRY_NAME:-diene-aluminium-registry-${path_key}}"
delete_cluster="${K3D_DELETE_CLUSTER:-true}"
delete_registry="${K3D_DELETE_REGISTRY:-true}"
result=0

if [ "${delete_cluster}" = "true" ] && k3d cluster list --no-headers | awk -v name="${cluster_name}" '$1 == name { found = 1 } END { exit !found }'; then
  if ! k3d cluster delete "${cluster_name}"; then
    echo "❌ failed to delete k3d cluster ${cluster_name}" >&2
    result=1
  fi
else
  echo "✅ k3d cluster ${cluster_name} cleanup skipped or already absent"
fi

if [ "${delete_registry}" = "true" ] && k3d registry list --no-headers | awk -v name="${registry_name}" '$1 == name || $1 == "k3d-" name { found = 1 } END { exit !found }'; then
  if ! k3d registry delete "${registry_name}"; then
    echo "❌ failed to delete k3d registry ${registry_name}" >&2
    result=1
  fi
else
  echo "✅ k3d registry ${registry_name} cleanup skipped or already absent"
fi

if [ "${result}" -eq 0 ]; then
  echo "✅ requested k3d cleanup completed"
else
  echo "❌ requested k3d cleanup incomplete" >&2
fi
exit "${result}"
