#!/usr/bin/env bash
set -euo pipefail

# Non-live conformance for the k3d integration tier. Two focused checks run with
# zero live infrastructure:
#   1. behavioral — the create/delete helpers enforce the same per-invocation
#      ownership/isolation contract on every public path, using a fake k3d
#      backend on PATH (no cluster, registry, or Docker daemon is touched);
#   2. structural — the proof wrapper performs the two-phase Helm-managed CRD
#      bootstrap in the required order (store disabled, wait for the v1
#      ClusterSecretStore CRD Established, then the full upgrade/install).

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${repo_root}"

workdir="$(mktemp -d)"
trap 'rm -rf "${workdir}"' EXIT

bindir="${workdir}/bin"
mkdir -p "${bindir}"

# Fake k3d: cluster/registry existence is driven by FAKE_K3D_CLUSTERS and
# FAKE_K3D_REGISTRIES; create/delete only record the requested action.
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
# passes VAR=value tokens before the script path.
run_helper() {
  local script="$1"
  shift
  env -u K3D_ISOLATE_BY_PATH -u K3D_OWNERSHIP_MARKER -u K3D_OWNER_ID \
    -u K3D_CLUSTER_NAME -u K3D_REGISTRY_NAME \
    FAKE_K3D_LOG="${FAKE_K3D_LOG:-/dev/null}" \
    FAKE_K3D_CLUSTERS="${FAKE_K3D_CLUSTERS:-}" \
    FAKE_K3D_REGISTRIES="${FAKE_K3D_REGISTRIES:-}" \
    "$@" bash "./scripts/local/${script}"
}

create="create-k3d-cluster.sh"
delete="delete-k3d-cluster.sh"
cluster="diene-cobalt-fake"
registry="diene-cobalt-registry-fake"

# --- create: contract refusals -------------------------------------------------
run_helper "${create}" K3D_OWNERSHIP_MARKER="${workdir}/m1" K3D_OWNER_ID=o \
  K3D_CLUSTER_NAME="${cluster}" K3D_REGISTRY_NAME="${registry}" 2>/dev/null &&
  fail "create accepted a run without K3D_ISOLATE_BY_PATH"

run_helper "${create}" K3D_ISOLATE_BY_PATH=true K3D_OWNER_ID=o \
  K3D_CLUSTER_NAME="${cluster}" K3D_REGISTRY_NAME="${registry}" 2>/dev/null &&
  fail "create accepted a run without an ownership marker"

run_helper "${create}" K3D_ISOLATE_BY_PATH=true K3D_OWNERSHIP_MARKER="rel/marker" \
  K3D_OWNER_ID=o K3D_CLUSTER_NAME="${cluster}" K3D_REGISTRY_NAME="${registry}" 2>/dev/null &&
  fail "create accepted a relative ownership marker"

run_helper "${create}" K3D_ISOLATE_BY_PATH=true K3D_OWNERSHIP_MARKER="${workdir}/m2" \
  K3D_CLUSTER_NAME="${cluster}" K3D_REGISTRY_NAME="${registry}" 2>/dev/null &&
  fail "create accepted a run without an owner id"

FAKE_K3D_CLUSTERS="${cluster}" \
  run_helper "${create}" K3D_ISOLATE_BY_PATH=true K3D_OWNERSHIP_MARKER="${workdir}/m3" \
  K3D_OWNER_ID=o K3D_CLUSTER_NAME="${cluster}" K3D_REGISTRY_NAME="${registry}" 2>/dev/null &&
  fail "create adopted a pre-existing cluster"
[ -e "${workdir}/m3" ] && fail "create wrote a marker while refusing an existing cluster"

FAKE_K3D_REGISTRIES="${registry}" \
  run_helper "${create}" K3D_ISOLATE_BY_PATH=true K3D_OWNERSHIP_MARKER="${workdir}/m4" \
  K3D_OWNER_ID=o K3D_CLUSTER_NAME="${cluster}" K3D_REGISTRY_NAME="${registry}" 2>/dev/null &&
  fail "create adopted a pre-existing registry"

: >"${workdir}/m5"
run_helper "${create}" K3D_ISOLATE_BY_PATH=true K3D_OWNERSHIP_MARKER="${workdir}/m5" \
  K3D_OWNER_ID=o K3D_CLUSTER_NAME="${cluster}" K3D_REGISTRY_NAME="${registry}" 2>/dev/null &&
  fail "create reused a pre-existing marker path"

# --- create: contract success --------------------------------------------------
marker="${workdir}/owner-good"
run_helper "${create}" K3D_ISOLATE_BY_PATH=true K3D_OWNERSHIP_MARKER="${marker}" \
  K3D_OWNER_ID=owner-x K3D_CLUSTER_NAME="${cluster}" K3D_REGISTRY_NAME="${registry}" >/dev/null ||
  fail "create rejected a fully specified contract"
[ -f "${marker}" ] || fail "create did not write the ownership marker"
expected="$(printf 'cluster=%s\nregistry=%s\nowner=%s' "${cluster}" "${registry}" owner-x)"
[ "$(cat "${marker}")" = "${expected}" ] || fail "marker content does not record the invocation triple"

# --- delete: contract refusals -------------------------------------------------
run_helper "${delete}" K3D_OWNERSHIP_MARKER="${marker}" K3D_OWNER_ID=owner-x \
  K3D_CLUSTER_NAME="${cluster}" K3D_REGISTRY_NAME="${registry}" 2>/dev/null &&
  fail "delete accepted a run without K3D_ISOLATE_BY_PATH"

run_helper "${delete}" K3D_ISOLATE_BY_PATH=true K3D_OWNERSHIP_MARKER="${workdir}/absent" \
  K3D_OWNER_ID=owner-x K3D_CLUSTER_NAME="${cluster}" K3D_REGISTRY_NAME="${registry}" 2>/dev/null &&
  fail "delete accepted a run without a marker file"

run_helper "${delete}" K3D_ISOLATE_BY_PATH=true K3D_OWNERSHIP_MARKER="${marker}" \
  K3D_OWNER_ID=wrong-owner K3D_CLUSTER_NAME="${cluster}" K3D_REGISTRY_NAME="${registry}" 2>/dev/null &&
  fail "delete accepted a mismatched owner"
[ -f "${marker}" ] || fail "delete removed the marker after refusing a mismatched owner"

# --- delete: contract success --------------------------------------------------
del_log="${workdir}/delete.log"
FAKE_K3D_LOG="${del_log}" FAKE_K3D_CLUSTERS="${cluster}" FAKE_K3D_REGISTRIES="${registry}" \
  run_helper "${delete}" K3D_ISOLATE_BY_PATH=true K3D_OWNERSHIP_MARKER="${marker}" \
  K3D_OWNER_ID=owner-x K3D_CLUSTER_NAME="${cluster}" K3D_REGISTRY_NAME="${registry}" >/dev/null ||
  fail "delete rejected the matching-owner cleanup"
[ -e "${marker}" ] && fail "delete left the ownership marker behind"
rg -qx "cluster-delete ${cluster}" "${del_log}" || fail "delete did not remove the owned cluster"
rg -qx "registry-delete ${registry}" "${del_log}" || fail "delete did not remove the owned registry"

# --- structural: two-phase CRD bootstrap ordering ------------------------------
proof="scripts/validate/cobalt-k3d.sh"
disable_line="$(rg -n -- '--set store.enabled=false' "${proof}" | head -1 | cut -d: -f1)"
established_line="$(rg -n -- 'condition=Established crd/clustersecretstores.external-secrets.io' "${proof}" | head -1 | cut -d: -f1)"
full_line="$(rg -n -- '--values chart/values.lapras.yaml --wait --timeout 5m' "${proof}" | head -1 | cut -d: -f1)"
store_assert_line="$(rg -n -- 'get clustersecretstore cobalt-sos' "${proof}" | head -1 | cut -d: -f1)"

[ -n "${disable_line}" ] || fail "proof wrapper never disables the store for phase 1"
[ -n "${established_line}" ] || fail "proof wrapper never waits for the ClusterSecretStore CRD to be Established"
[ -n "${full_line}" ] || fail "proof wrapper never runs the full phase-2 upgrade/install"
[ -n "${store_assert_line}" ] || fail "proof wrapper never asserts the cobalt-sos store"
[ "${disable_line}" -lt "${established_line}" ] || fail "store disable must precede the CRD Established wait"
[ "${established_line}" -lt "${full_line}" ] || fail "CRD Established wait must precede the full install"
[ "${full_line}" -lt "${store_assert_line}" ] || fail "full install must precede the store assertion"

# --- command-runner contract: RESULT_DIR (RB-243 regression) -------------------
# The proof wrapper must make the runner's absolute-durable-evidence-root contract
# explicit. When RESULT_DIR is omitted it must refuse with a self-describing
# message and must NOT die on the opaque `unbound variable` that produced the
# RB-243 terminal-red campaign; a relative RESULT_DIR must be refused; and an
# absolute RESULT_DIR must pass the contract (reaching the no-overwrite guard)
# without invoking any live infrastructure.
proofwrap="scripts/validate/cobalt-k3d-proof.sh"

if unset_out="$(env -u RESULT_DIR bash "./${proofwrap}" 2>&1)"; then
  fail "proof wrapper accepted a run with RESULT_DIR unset"
fi
rg -q "must be exported by the command runner" <<<"${unset_out}" ||
  fail "proof wrapper did not explain the missing RESULT_DIR contract"
if rg -qi "unbound variable" <<<"${unset_out}"; then
  fail "proof wrapper still dies on an unbound RESULT_DIR (RB-243 regression)"
fi

if rel_out="$(RESULT_DIR="relative/evidence" bash "./${proofwrap}" 2>&1)"; then
  fail "proof wrapper accepted a relative RESULT_DIR"
fi
rg -q "RESULT_DIR must be an absolute path" <<<"${rel_out}" ||
  fail "proof wrapper did not reject a relative RESULT_DIR"

# Absolute RESULT_DIR passes the contract; a pre-seeded artifact trips the
# no-overwrite guard so the check stops before any k3d/Helm/Docker call. Reaching
# that guard proves the absolute result root was accepted.
abs_root="${workdir}/result-abs"
mkdir -p "${abs_root}/evidence"
: >"${abs_root}/evidence/cobalt-k3d.log"
if abs_out="$(RESULT_DIR="${abs_root}" bash "./${proofwrap}" 2>&1)"; then
  fail "proof wrapper ran the live proof under the non-live contract check"
fi
rg -q "refusing to overwrite pre-existing evidence artifact" <<<"${abs_out}" ||
  fail "proof wrapper did not accept an absolute RESULT_DIR and root evidence under it"

# Structural: the contract guard must precede any use of the result root.
guard_line="$(rg -n -- 'RESULT_DIR:\?' "${proofwrap}" | head -1 | cut -d: -f1)"
evroot_line="$(rg -n -F -- 'evidence_dir="${result_dir}' "${proofwrap}" | head -1 | cut -d: -f1)"
[ -n "${guard_line}" ] || fail "proof wrapper never guards RESULT_DIR with an explicit contract"
[ -n "${evroot_line}" ] || fail "proof wrapper never roots evidence under RESULT_DIR"
[ "${guard_line}" -lt "${evroot_line}" ] || fail "RESULT_DIR contract guard must precede evidence-path derivation"

echo "✅ Cobalt k3d contract validation passed"
