#!/usr/bin/env bash
set -euo pipefail

cluster_name="${K3D_CLUSTER_NAME:-diene-zinc}"
registry_name="${K3D_REGISTRY_NAME:-diene-zinc-registry}"
registry_port="${K3D_REGISTRY_PORT:-5001}"
http_port="${K3D_HTTP_PORT:-18080}"
# Strict ownership (opt-in via the isolated proof and the public lifecycle wrapper):
# never adopt a pre-existing cluster/registry, and — once the preflight has proved
# the exact names are absent — pre-reserve them in the marker BEFORE invoking k3d so
# the caller's transactional cleanup tears down exactly what THIS attempt may have
# built, even across a partial `k3d cluster create` that fails after creating some
# resources.
require_ownership="${K3D_REQUIRE_OWNERSHIP:-false}"
ownership_marker="${K3D_OWNERSHIP_MARKER:-}"

cluster_exists="$(k3d cluster list --no-headers | awk '{print $1}' | rg -qx "${cluster_name}" && echo true || echo false)"
# k3d prefixes managed registries with `k3d-`; match either form so ownership and
# collision checks are robust to the prefix.
registry_exists="$(k3d registry list --no-headers | awk '{print $1}' | rg -qx "(k3d-)?${registry_name}" && echo true || echo false)"

# Fail closed on collision under strict ownership so the run cannot destroy a
# cluster/registry it did not create.
[ "${require_ownership}" = "true" ] && [ "${cluster_exists}" = "true" ] && echo "❌ k3d cluster ${cluster_name} already exists; refusing to adopt a cluster this run does not own" >&2 && exit 1
[ "${require_ownership}" = "true" ] && [ "${registry_exists}" = "true" ] && echo "❌ k3d registry ${registry_name} already exists; refusing to adopt a registry this run does not own" >&2 && exit 1

# Idempotent reuse for the standalone start:cluster task: an existing cluster is a
# success (this path is disabled under strict ownership by the guards above).
[ "${cluster_exists}" = "true" ] && echo "✅ k3d cluster ${cluster_name} already exists" && exit 0

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

# Transactional pre-reservation: under strict ownership the collision preflight above
# already proved these exact names are absent, so claim them BEFORE creating anything.
# If `k3d cluster create` builds the registry and/or cluster and then exits non-zero,
# the marker still names exactly what this attempt may have created — so the caller's
# transactional cleanup tears those (and only those) down and a partial create never
# leaks.
if [ "${require_ownership}" = "true" ] && [ -n "${ownership_marker}" ]; then
  printf 'cluster=%s\nregistry=%s\n' "${cluster_name}" "${registry_name}" >"${ownership_marker}"
fi

k3d cluster create --config "${config}"

# Non-strict callers (no preflight-proved absence) record ownership only on a
# successful create.
if [ "${require_ownership}" != "true" ] && [ -n "${ownership_marker}" ]; then
  printf 'cluster=%s\nregistry=%s\n' "${cluster_name}" "${registry_name}" >"${ownership_marker}"
fi

echo "✅ k3d cluster ${cluster_name} created"
