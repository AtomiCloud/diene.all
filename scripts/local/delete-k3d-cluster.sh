#!/usr/bin/env bash
set -euo pipefail

cluster_name="${K3D_CLUSTER_NAME:-diene-sulfur}"
registry_name="${K3D_REGISTRY_NAME:-diene-sulfur-registry}"
# Strict ownership (opt-in via the isolated proof): delete ONLY the cluster/registry
# a prior create claimed in the marker. No/invalid marker means nothing was owned,
# so nothing is deleted — a pre-existing, unowned cluster is never destroyed.
require_ownership="${K3D_REQUIRE_OWNERSHIP:-false}"
ownership_marker="${K3D_OWNERSHIP_MARKER:-}"

[ "${require_ownership}" = "true" ] && { [ -z "${ownership_marker}" ] || [ ! -f "${ownership_marker}" ]; } && echo "✅ no owned k3d resources to delete" && exit 0
[ "${require_ownership}" = "true" ] && cluster_name="$(rg -N '^cluster=' "${ownership_marker}" | cut -d= -f2)"
[ "${require_ownership}" = "true" ] && registry_name="$(rg -N '^registry=' "${ownership_marker}" | cut -d= -f2)"

if k3d cluster list --no-headers | awk '{print $1}' | rg -qx "${cluster_name}"; then
  k3d cluster delete "${cluster_name}"
else
  echo "✅ k3d cluster ${cluster_name} is already absent"
fi

# k3d prefixes managed registries with `k3d-`; match either form.
if k3d registry list --no-headers | awk '{print $1}' | rg -qx "(k3d-)?${registry_name}"; then
  k3d registry delete "${registry_name}"
fi

echo "✅ k3d cluster ${cluster_name} deleted"
