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

# Ownership safety: a pre-existing cluster of this name is NOT proof that this
# sandbox owns it (it could be foreign or stale). Refuse to reuse it rather than
# silently install/mutate/delete inside it; the caller must tear it down first
# with delete-k3d-cluster.sh.
if k3d cluster list --no-headers | awk '{print $1}' | rg -qx "${cluster_name}"; then
  echo "❌ k3d cluster ${cluster_name} already exists; refusing to reuse (run delete-k3d-cluster.sh first)" >&2
  exit 1
fi

config="$(mktemp)"
trap 'rm -f "${config}"' EXIT

yq eval '
  .metadata.name = strenv(K3D_CLUSTER_NAME) |
  .registries.create.name = strenv(K3D_REGISTRY_NAME) |
  .registries.create.hostPort = strenv(K3D_REGISTRY_PORT) |
  .ports[0].port = (strenv(K3D_HTTP_PORT) + ":80")
' infra/k3d.lapras.yaml >"${config}"

k3d cluster create --config "${config}"

echo "✅ k3d cluster ${cluster_name} created (context k3d-${cluster_name}, registry ${registry_name}:${registry_port}, http ${http_port})"
