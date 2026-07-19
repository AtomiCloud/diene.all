#!/usr/bin/env bash
set -euo pipefail

cluster_name="${K3D_CLUSTER_NAME:?set K3D_CLUSTER_NAME}"
registry_name="${K3D_REGISTRY_NAME:?set K3D_REGISTRY_NAME}"
registry_port="${K3D_REGISTRY_PORT:?set K3D_REGISTRY_PORT}"
http_port="${K3D_HTTP_PORT:?set K3D_HTTP_PORT}"

k3d cluster list --no-headers | awk '{print $1}' | rg -qx "${cluster_name}" && echo "❌ k3d cluster ${cluster_name} already exists" >&2 && exit 1
k3d registry list --no-headers | awk '{print $1}' | rg -qx "${registry_name}" && echo "❌ k3d registry ${registry_name} already exists" >&2 && exit 1
ss -ltn | awk '{print $4}' | rg -q "[:.]${registry_port}$|[:.]${http_port}$" && echo "❌ requested k3d port already in use" >&2 && exit 1

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
' infra/vanadium-k3d.yaml >"${config}"

k3d cluster create --config "${config}"

echo "✅ k3d cluster ${cluster_name} created"
