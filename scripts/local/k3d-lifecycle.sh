#!/usr/bin/env bash
# Ownership-aware public lifecycle wrapper for the local k3d proof cluster
# (the `start:cluster` / `stop:cluster` Taskfile surface).
#
# The ephemeral strict proof derives a per-run ownership marker under mktemp, but the
# public lifecycle spans two separate invocations, so it needs a DURABLE, private
# marker: a later `stop` must tear down only what an earlier `start` built. Without
# this, `start` silently adopts a pre-existing (default-named) cluster and `stop`
# unconditionally destroys it — the same unsafe adopt-then-delete lifecycle the strict
# proof mode already fixed.
#
# Contract:
#   start — fail closed on an UNOWNED pre-existing cluster/registry (never adopt);
#           record exactly the resources this run creates in the durable marker; a
#           re-start of an already-owned cluster is an idempotent success.
#   stop  — delete ONLY the cluster/registry named in the durable marker; with no
#           marker, delete nothing (a pre-existing, unowned cluster is never
#           destroyed) and then clear the marker. `K3D_FORCE=true` is the explicit
#           escape hatch: delete the default-named cluster/registry regardless of the
#           marker.
set -euo pipefail

action="${1:-}"
cluster_name="${K3D_CLUSTER_NAME:-diene-zinc}"
registry_name="${K3D_REGISTRY_NAME:-diene-zinc-registry}"
state_home="${XDG_STATE_HOME:-${HOME}/.local/state}"
# Durable, private marker (outside the repository tree) keyed by cluster identity.
marker="${K3D_OWNERSHIP_MARKER:-${state_home}/diene-zinc/${cluster_name}.owned}"

[ -z "${action}" ] && echo "❌ usage: k3d-lifecycle.sh <start|stop>" >&2 && exit 1

cluster_present() {
  k3d cluster list --no-headers 2>/dev/null | awk '{print $1}' | rg -qx "${cluster_name}"
}

case "${action}" in
start)
  mkdir -p "$(dirname "${marker}")"
  # Idempotent re-start: if the durable marker proves THIS lifecycle already owns the
  # running cluster, report success without touching it.
  if [ -f "${marker}" ] && rg -qx "cluster=${cluster_name}" "${marker}" && cluster_present; then
    echo "✅ k3d cluster ${cluster_name} already owned and running"
    exit 0
  fi
  # Otherwise create under strict ownership: create-k3d-cluster.sh fails closed on any
  # pre-existing (unowned) cluster/registry and pre-reserves exactly what it builds in
  # the durable marker.
  K3D_CLUSTER_NAME="${cluster_name}" K3D_REGISTRY_NAME="${registry_name}" \
    K3D_REQUIRE_OWNERSHIP=true K3D_OWNERSHIP_MARKER="${marker}" \
    bash ./scripts/local/create-k3d-cluster.sh
  ;;
stop)
  if [ "${K3D_FORCE:-false}" = "true" ]; then
    # Explicit force: delete the default-named resources regardless of the marker.
    K3D_CLUSTER_NAME="${cluster_name}" K3D_REGISTRY_NAME="${registry_name}" \
      bash ./scripts/local/delete-k3d-cluster.sh
    rm -f "${marker}"
    exit 0
  fi
  # Ownership-scoped stop: delete only what the durable marker records; no marker means
  # nothing is owned, so nothing is destroyed.
  K3D_REQUIRE_OWNERSHIP=true K3D_OWNERSHIP_MARKER="${marker}" \
    bash ./scripts/local/delete-k3d-cluster.sh
  rm -f "${marker}"
  ;;
*)
  echo "❌ unknown lifecycle action '${action}' (expected start|stop)" >&2
  exit 1
  ;;
esac
