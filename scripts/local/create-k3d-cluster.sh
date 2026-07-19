#!/usr/bin/env bash
set -euo pipefail

cluster_name="${K3D_CLUSTER_NAME:-diene-cobalt}"
registry_name="${K3D_REGISTRY_NAME:-diene-cobalt-registry}"
registry_port="${K3D_REGISTRY_PORT:-5001}"
http_port="${K3D_HTTP_PORT:-18080}"
ownership_marker="${K3D_OWNERSHIP_MARKER:-}"
owner_id="${K3D_OWNER_ID:-}"

if [ -n "${ownership_marker}" ]; then
  [ "${ownership_marker#/}" != "${ownership_marker}" ] || {
    echo "❌ K3D_OWNERSHIP_MARKER must be an absolute path" >&2
    exit 1
  }
  [ -n "${owner_id}" ] || {
    echo "❌ K3D_OWNER_ID is required with K3D_OWNERSHIP_MARKER" >&2
    exit 1
  }
  [ ! -e "${ownership_marker}" ] || {
    echo "❌ ownership marker already exists: ${ownership_marker}" >&2
    exit 1
  }
  if k3d cluster list --no-headers | awk '{print $1}' | rg -qx "${cluster_name}"; then
    echo "❌ refusing to adopt existing k3d cluster ${cluster_name}" >&2
    exit 1
  fi
  if k3d registry list --no-headers | awk '{print $1}' | rg -qx "${registry_name}"; then
    echo "❌ refusing to adopt existing k3d registry ${registry_name}" >&2
    exit 1
  fi
  mkdir -p "$(dirname "${ownership_marker}")"
  if ! (
    set -o noclobber
    printf 'cluster=%s\nregistry=%s\nowner=%s\n' "${cluster_name}" "${registry_name}" "${owner_id}" >"${ownership_marker}"
  ); then
    echo "❌ ownership marker collision: ${ownership_marker}" >&2
    exit 1
  fi
else
  k3d cluster list --no-headers | awk '{print $1}' | rg -qx "${cluster_name}" && echo "✅ k3d cluster ${cluster_name} already exists" && exit 0
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
