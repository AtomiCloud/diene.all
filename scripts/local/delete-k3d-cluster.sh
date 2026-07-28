#!/usr/bin/env bash
set -euo pipefail

cluster_name="${K3D_CLUSTER_NAME:-diene-cobalt}"
registry_name="${K3D_REGISTRY_NAME:-diene-cobalt-registry}"
ownership_marker="${K3D_OWNERSHIP_MARKER:-}"
owner_id="${K3D_OWNER_ID:-}"

# Deletion demands the same per-invocation contract as creation and only removes
# resources whose marker records this exact cluster/registry/owner triple.
[ "${K3D_ISOLATE_BY_PATH:-}" = "true" ] || {
  echo "❌ K3D_ISOLATE_BY_PATH=true is mandatory to delete a k3d cluster" >&2
  exit 1
}
[ -n "${ownership_marker}" ] || {
  echo "❌ K3D_OWNERSHIP_MARKER is required" >&2
  exit 1
}
[ "${ownership_marker#/}" != "${ownership_marker}" ] || {
  echo "❌ K3D_OWNERSHIP_MARKER must be an absolute path" >&2
  exit 1
}
[ -n "${owner_id}" ] || {
  echo "❌ K3D_OWNER_ID is required with K3D_OWNERSHIP_MARKER" >&2
  exit 1
}
[ -f "${ownership_marker}" ] || {
  echo "❌ refusing cleanup without ownership marker ${ownership_marker}" >&2
  exit 1
}
expected="$(printf 'cluster=%s\nregistry=%s\nowner=%s' "${cluster_name}" "${registry_name}" "${owner_id}")"
[ "$(cat "${ownership_marker}")" = "${expected}" ] || {
  echo "❌ ownership marker does not match requested k3d cleanup" >&2
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

rm -f "${ownership_marker}"

echo "✅ k3d cluster ${cluster_name} deleted"
