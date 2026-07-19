#!/usr/bin/env bash
# ### chlorine-k3d-contract
# #### source: chlorine
#
# Non-live conformance for the k3d integration tier's ownership contract
# (RB-66 rev2). Runs with a fake k3d backend on PATH — no cluster, registry,
# Docker daemon, or kube context is ever touched — and proves the create/delete
# helpers enforce the per-invocation ownership marker on every path:
#   * collision → no-delete: create refuses a foreign cluster/registry WITHOUT
#     writing a marker, so the unconditional teardown that follows finds no
#     matching marker and deletes nothing;
#   * mismatch refusal: delete refuses a marker whose recorded owner/pair does
#     not match the requested teardown, and leaves that marker in place;
#   * matching-owner cleanup: delete with the marker create wrote removes exactly
#     the recorded cluster+registry pair and only then the marker.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${repo_root}"

workdir="$(mktemp -d)"
trap 'rm -rf "${workdir}"' EXIT

bindir="${workdir}/bin"
mkdir -p "${bindir}"

# Fake k3d: cluster/registry existence is driven by FAKE_K3D_CLUSTERS and
# FAKE_K3D_REGISTRIES; create/delete only append the requested action to the log
# so a test can assert exactly which resources were (not) touched.
cat >"${bindir}/k3d" <<'FAKE'
#!/usr/bin/env bash
set -euo pipefail
log="${FAKE_K3D_LOG:-/dev/null}"
case "${1:-} ${2:-}" in
"cluster list")
  for c in ${FAKE_K3D_CLUSTERS:-}; do echo "${c} 1/1"; done
  ;;
"registry list")
  for r in ${FAKE_K3D_REGISTRIES:-}; do echo "${r} running"; done
  ;;
"cluster create")
  echo "cluster-create" >>"${log}"
  ;;
"cluster delete")
  echo "cluster-delete ${3:-}" >>"${log}"
  ;;
"registry delete")
  echo "registry-delete ${3:-}" >>"${log}"
  ;;
*)
  echo "fake-k3d: unhandled invocation: $*" >&2
  exit 2
  ;;
esac
FAKE
chmod +x "${bindir}/k3d"

export PATH="${bindir}:${PATH}"

fail() {
  echo "❌ $1" >&2
  exit 1
}

# Run a helper with a scrubbed contract env plus the given overrides; the caller
# passes VAR=value tokens before the script name. The isolation key is pinned so
# the derived cluster/registry names are deterministic and git-independent.
run_helper() {
  local script="$1"
  shift
  env -u K3D_OWNERSHIP_MARKER -u K3D_OWNER_ID \
    -u K3D_CLUSTER_NAME -u K3D_REGISTRY_NAME \
    K3D_ISOLATION_KEY=contract \
    FAKE_K3D_LOG="${FAKE_K3D_LOG:-/dev/null}" \
    FAKE_K3D_CLUSTERS="${FAKE_K3D_CLUSTERS:-}" \
    FAKE_K3D_REGISTRIES="${FAKE_K3D_REGISTRIES:-}" \
    "$@" bash "./scripts/local/${script}"
}

create="create-k3d-cluster.sh"
delete="delete-k3d-cluster.sh"
cluster="diene-chlorine-fake"
registry="diene-chlorine-reg-fake"

# --- create: contract refusals -------------------------------------------------
run_helper "${create}" K3D_OWNER_ID=o \
  K3D_CLUSTER_NAME="${cluster}" K3D_REGISTRY_NAME="${registry}" 2>/dev/null &&
  fail "create accepted a run without an ownership marker"

run_helper "${create}" K3D_OWNERSHIP_MARKER="rel/marker" K3D_OWNER_ID=o \
  K3D_CLUSTER_NAME="${cluster}" K3D_REGISTRY_NAME="${registry}" 2>/dev/null &&
  fail "create accepted a relative ownership marker"

run_helper "${create}" K3D_OWNERSHIP_MARKER="${workdir}/m-noowner" \
  K3D_CLUSTER_NAME="${cluster}" K3D_REGISTRY_NAME="${registry}" 2>/dev/null &&
  fail "create accepted a run without an owner id"
[ -e "${workdir}/m-noowner" ] && fail "create wrote a marker while refusing a run without an owner id"

: >"${workdir}/m-present"
run_helper "${create}" K3D_OWNERSHIP_MARKER="${workdir}/m-present" K3D_OWNER_ID=o \
  K3D_CLUSTER_NAME="${cluster}" K3D_REGISTRY_NAME="${registry}" 2>/dev/null &&
  fail "create reused a pre-existing marker path"

# --- collision → no-delete -----------------------------------------------------
# A foreign cluster of this name pre-exists: create must refuse it WITHOUT
# writing a marker...
collision_marker="${workdir}/m-collision"
FAKE_K3D_CLUSTERS="${cluster}" \
  run_helper "${create}" K3D_OWNERSHIP_MARKER="${collision_marker}" K3D_OWNER_ID=o \
  K3D_CLUSTER_NAME="${cluster}" K3D_REGISTRY_NAME="${registry}" 2>/dev/null &&
  fail "create adopted a pre-existing cluster"
[ -e "${collision_marker}" ] && fail "create wrote a marker while refusing an existing cluster"

# ...and a foreign registry of this name is refused the same way.
FAKE_K3D_REGISTRIES="${registry}" \
  run_helper "${create}" K3D_OWNERSHIP_MARKER="${workdir}/m-reg-collision" K3D_OWNER_ID=o \
  K3D_CLUSTER_NAME="${cluster}" K3D_REGISTRY_NAME="${registry}" 2>/dev/null &&
  fail "create adopted a pre-existing registry"
[ -e "${workdir}/m-reg-collision" ] && fail "create wrote a marker while refusing an existing registry"

# The teardown that unconditionally follows a create refusal presents that same
# (never written) marker: with no marker file it must refuse and touch nothing,
# so the foreign cluster/registry it would otherwise delete is left intact.
nodelete_log="${workdir}/nodelete.log"
: >"${nodelete_log}"
FAKE_K3D_LOG="${nodelete_log}" FAKE_K3D_CLUSTERS="${cluster}" FAKE_K3D_REGISTRIES="${registry}" \
  run_helper "${delete}" K3D_OWNERSHIP_MARKER="${collision_marker}" K3D_OWNER_ID=o \
  K3D_CLUSTER_NAME="${cluster}" K3D_REGISTRY_NAME="${registry}" 2>/dev/null &&
  fail "delete removed a foreign cluster/registry with no ownership marker"
[ -s "${nodelete_log}" ] && fail "delete mutated k3d without an ownership marker"

# --- create: contract success --------------------------------------------------
marker="${workdir}/owner-good"
run_helper "${create}" K3D_OWNERSHIP_MARKER="${marker}" K3D_OWNER_ID=owner-x \
  K3D_CLUSTER_NAME="${cluster}" K3D_REGISTRY_NAME="${registry}" >/dev/null ||
  fail "create rejected a fully specified contract on a clean backend"
[ -f "${marker}" ] || fail "create did not write the ownership marker"
expected="$(printf 'cluster=%s\nregistry=%s\nowner=%s' "${cluster}" "${registry}" owner-x)"
[ "$(cat "${marker}")" = "${expected}" ] || fail "marker content does not record the invocation triple"

# --- delete: mismatch refusal --------------------------------------------------
run_helper "${delete}" K3D_OWNERSHIP_MARKER="${workdir}/absent" K3D_OWNER_ID=owner-x \
  K3D_CLUSTER_NAME="${cluster}" K3D_REGISTRY_NAME="${registry}" 2>/dev/null &&
  fail "delete accepted a run without a marker file"

run_helper "${delete}" K3D_OWNERSHIP_MARKER="${marker}" K3D_OWNER_ID=wrong-owner \
  K3D_CLUSTER_NAME="${cluster}" K3D_REGISTRY_NAME="${registry}" 2>/dev/null &&
  fail "delete accepted a mismatched owner"
[ -f "${marker}" ] || fail "delete removed the marker after refusing a mismatched owner"

# --- matching-owner cleanup ----------------------------------------------------
del_log="${workdir}/delete.log"
: >"${del_log}"
FAKE_K3D_LOG="${del_log}" FAKE_K3D_CLUSTERS="${cluster}" FAKE_K3D_REGISTRIES="${registry}" \
  run_helper "${delete}" K3D_OWNERSHIP_MARKER="${marker}" K3D_OWNER_ID=owner-x \
  K3D_CLUSTER_NAME="${cluster}" K3D_REGISTRY_NAME="${registry}" >/dev/null ||
  fail "delete rejected the matching-owner cleanup"
[ -e "${marker}" ] && fail "delete left the ownership marker behind after teardown"
rg -qx "cluster-delete ${cluster}" "${del_log}" || fail "delete did not remove the owned cluster"
rg -qx "registry-delete ${registry}" "${del_log}" || fail "delete did not remove the owned registry"

echo "✅ Chlorine k3d contract validation passed"
