#!/usr/bin/env bash
set -euo pipefail

path_key="$(printf '%s' "${PWD}" | sha256sum | cut -c1-8)"
cluster_name="${K3D_CLUSTER_NAME:-diene-aluminium-${path_key}}"
registry_name="${K3D_REGISTRY_NAME:-diene-aluminium-registry-${path_key}}"
registry_port="${K3D_REGISTRY_PORT:-$((20000 + (16#${path_key:0:4} % 10000)))}"
http_port="${K3D_HTTP_PORT:-$((30000 + (16#${path_key:4:4} % 10000)))}"

if k3d cluster list --no-headers | awk -v name="${cluster_name}" '$1 == name { found = 1 } END { exit !found }'; then
  echo "❌ k3d cluster ${cluster_name} already exists; refusing to reuse it" >&2
  exit 1
fi
if k3d registry list --no-headers | awk -v name="${registry_name}" '$1 == name || $1 == "k3d-" name { found = 1 } END { exit !found }'; then
  echo "❌ k3d registry ${registry_name} already exists; refusing to reuse it" >&2
  exit 1
fi

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
