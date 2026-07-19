#!/usr/bin/env bash
# ### chlorine-k3d-isolation
# #### source: chlorine
#
# Sandbox isolation for the k3d integration proof (helm-wrapper RB-66). Parallel
# sandboxes must NEVER share one fixed cluster, registry, registry port, HTTP
# port, or kube context: a concurrent probe could otherwise bind, mutate, or
# delete another sandbox's live resources. Every live identifier is derived from
# a path-keyed isolation key (K3D_ISOLATION_KEY, defaulting to a short hash of
# the worktree toplevel), and the kube context is pinned to the explicit
# k3d-<cluster> name so no command ever relies on k3d mutating the ambient
# current-context. Sourced by create/delete/validate so all three agree on the
# same identifiers; the proof handoff may export K3D_ISOLATION_KEY (or any
# individual K3D_* name/port) to pin the sandbox, and those overrides win.

# Isolation key: explicit override, else a short hash of the worktree toplevel.
if [ -z "${K3D_ISOLATION_KEY:-}" ]; then
  _k3d_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
  K3D_ISOLATION_KEY="$(printf '%s' "${_k3d_root}" | sha256sum | cut -c1-8)"
fi
export K3D_ISOLATION_KEY

# Deterministic per-key offset (0-999) for the two host-published ports; cksum
# keeps this total for any key string (a pinned key need not be hex).
_k3d_offset="$(printf '%s' "${K3D_ISOLATION_KEY}" | cksum | cut -d' ' -f1)"
_k3d_offset=$((_k3d_offset % 1000))

export K3D_CLUSTER_NAME="${K3D_CLUSTER_NAME:-diene-chlorine-${K3D_ISOLATION_KEY}}"
export K3D_REGISTRY_NAME="${K3D_REGISTRY_NAME:-diene-chlorine-reg-${K3D_ISOLATION_KEY}}"
export K3D_REGISTRY_PORT="${K3D_REGISTRY_PORT:-$((5000 + _k3d_offset))}"
export K3D_HTTP_PORT="${K3D_HTTP_PORT:-$((18000 + _k3d_offset))}"
# k3d always prefixes the kube context with k3d-; pin it explicitly so every
# helm/kubectl call targets this sandbox instead of the ambient current-context.
export K3D_CONTEXT="${K3D_CONTEXT:-k3d-${K3D_CLUSTER_NAME}}"
