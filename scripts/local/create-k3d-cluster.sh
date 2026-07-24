#!/usr/bin/env bash
set -euo pipefail

# Sandbox isolation (RB-66): derive the cluster, registry, ports, and context
# from a path-keyed isolation key so parallel sandboxes never collide.
_here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${_here}/k3d-isolation.sh"

cluster_name="${K3D_CLUSTER_NAME}"
registry_name="${K3D_REGISTRY_NAME}"
registry_port="${K3D_REGISTRY_PORT}"
http_port="${K3D_HTTP_PORT}"
ownership_marker="${K3D_OWNERSHIP_MARKER:-}"
owner_id="${K3D_OWNER_ID:-}"

# Ownership contract (RB-66 rev2): a path-derived name reduces accidental
# collisions but is NOT an ownership marker — a pre-existing cluster/registry of
# this name could be foreign or stale. Require an absolute, initially absent
# marker plus an owner id; refuse any foreign collision WITHOUT claiming it; and
# write the marker only for a sandbox this invocation fully created. That way a
# later unconditional teardown presenting the same marker can never delete
# foreign resources: a create refusal leaves no marker, so delete refuses too.
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
[ ! -e "${ownership_marker}" ] || {
  echo "❌ ownership marker already exists: ${ownership_marker}" >&2
  exit 1
}
if k3d cluster list --no-headers | awk '{print $1}' | rg -qx "${cluster_name}"; then
  echo "❌ k3d cluster ${cluster_name} already exists; refusing to reuse (run delete-k3d-cluster.sh first)" >&2
  exit 1
fi
if k3d registry list --no-headers | awk '{print $1}' | rg -qx "${registry_name}"; then
  echo "❌ k3d registry ${registry_name} already exists; refusing to reuse (run delete-k3d-cluster.sh first)" >&2
  exit 1
fi

config="$(mktemp)"

# Every foreign collision was refused above without a marker, so any cluster or
# registry carrying these names now was created by THIS invocation. Roll back
# only those claimed resources (and a marker this run wrote) on failure; never
# touch anything that existed before this run.
created=0
marker_written=0
success=0
cleanup() {
  local rc=$?
  if [ "${success}" -ne 1 ]; then
    if [ "${created}" -eq 1 ]; then
      if k3d cluster list --no-headers | awk '{print $1}' | rg -qx "${cluster_name}"; then
        k3d cluster delete "${cluster_name}" || true
      fi
      if k3d registry list --no-headers | awk '{print $1}' | rg -qx "${registry_name}"; then
        k3d registry delete "${registry_name}" || true
      fi
    fi
    if [ "${marker_written}" -eq 1 ]; then
      rm -f "${ownership_marker}"
    fi
  fi
  rm -f "${config}"
  exit "${rc}"
}
trap cleanup EXIT

yq eval '
  .metadata.name = strenv(K3D_CLUSTER_NAME) |
  .registries.create.name = strenv(K3D_REGISTRY_NAME) |
  .registries.create.hostPort = strenv(K3D_REGISTRY_PORT) |
  .ports[0].port = (strenv(K3D_HTTP_PORT) + ":80")
' infra/k3d.lapras.yaml >"${config}"

created=1
k3d cluster create --config "${config}"

# The complete sandbox now exists: record ownership atomically (noclobber guards
# against a racing marker so we never clobber another invocation's claim) so
# teardown can prove it owns exactly this cluster/registry/owner triple.
mkdir -p "$(dirname "${ownership_marker}")"
marker_written=1
if ! (
  set -o noclobber
  printf 'cluster=%s\nregistry=%s\nowner=%s\n' "${cluster_name}" "${registry_name}" "${owner_id}" >"${ownership_marker}"
); then
  marker_written=0
  echo "❌ ownership marker collision: ${ownership_marker}" >&2
  exit 1
fi

success=1
echo "✅ k3d cluster ${cluster_name} created (context k3d-${cluster_name}, registry ${registry_name}:${registry_port}, http ${http_port})"
