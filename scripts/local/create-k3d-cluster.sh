#!/usr/bin/env bash
set -euo pipefail

cluster_name="${K3D_CLUSTER_NAME:-diene-zinc}"
registry_name="${K3D_REGISTRY_NAME:-diene-zinc-registry}"
registry_port="${K3D_REGISTRY_PORT:-5001}"
http_port="${K3D_HTTP_PORT:-18080}"

k3d cluster list --no-headers | awk '{print $1}' | rg -qx "${cluster_name}" && echo "✅ k3d cluster ${cluster_name} already exists" && exit 0

config="$(mktemp)"
trap 'rm -f "${config}"' EXIT

export K3D_CLUSTER_NAME="${cluster_name}"
export K3D_REGISTRY_NAME="${registry_name}"
export K3D_REGISTRY_PORT="${registry_port}"
export K3D_HTTP_PORT="${http_port}"
yq eval '
  .metadata.name = strenv(K3D_CLUSTER_NAME) |
  .registries.create.name = strenv(K3D_REGISTRY_NAME) |
  .registries.create.hostPort = strenv(K3D_REGISTRY_PORT) |
  .ports[0].port = (strenv(K3D_HTTP_PORT) + ":80")
' infra/k3d.lapras.yaml >"${config}"

k3d cluster create --config "${config}"

echo "✅ k3d cluster ${cluster_name} created"
