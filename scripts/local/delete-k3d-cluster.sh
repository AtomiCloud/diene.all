#!/usr/bin/env bash
set -euo pipefail

# Sandbox isolation (RB-66): resolve the same path-keyed cluster/registry the
# matching create step used so teardown only ever targets this sandbox.
_here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${_here}/k3d-isolation.sh"

cluster_name="${K3D_CLUSTER_NAME}"
registry_name="${K3D_REGISTRY_NAME}"
ownership_marker="${K3D_OWNERSHIP_MARKER:-}"
owner_id="${K3D_OWNER_ID:-}"

# Ownership contract (RB-66 rev2): teardown demands the same absolute marker and
# owner id create wrote, and only deletes the exact cluster/registry pair that
# marker records. Without a MATCHING marker this refuses — so an unconditional
# cleanup that runs after a create REFUSAL (which wrote no marker) never deletes
# a foreign or stale cluster/registry. The marker is removed only after a fully
# successful teardown.
[ -n "${ownership_marker}" ] || {
  echo "❌ K3D_OWNERSHIP_MARKER is required" >&2
  exit 1
}
[ "${ownership_marker#/}" != "${ownership_marker}" ] || {
  echo "❌ K3D_OWNERSHIP_MARKER must be an absolute path" >&2
  exit 1
}
[ -n "${owner_id}" ] || {
  echo "❌ K3D_OWNER_ID is required" >&2
  exit 1
}
[ -f "${ownership_marker}" ] || {
  echo "❌ refusing teardown without ownership marker ${ownership_marker}" >&2
  exit 1
}
expected="$(printf 'cluster=%s\nregistry=%s\nowner=%s' "${cluster_name}" "${registry_name}" "${owner_id}")"
[ "$(cat "${ownership_marker}")" = "${expected}" ] || {
  echo "❌ ownership marker does not record this cluster/registry/owner; refusing teardown" >&2
  exit 1
}

if k3d cluster list --no-headers | awk '{print $1}' | rg -qx "${cluster_name}"; then
  k3d cluster delete "${cluster_name}"
else
  echo "✅ k3d cluster ${cluster_name} is already absent"
fi

if k3d registry list --no-headers | awk '{print $1}' | rg -qx "${registry_name}"; then
  k3d registry delete "${registry_name}"
fi

# Marker removed ONLY after both resources are gone. set -euo pipefail aborts
# above on a failed delete, leaving the marker so a still-live sandbox stays
# claimed for a later retry.
rm -f "${ownership_marker}"

echo "✅ k3d cluster ${cluster_name} deleted"
