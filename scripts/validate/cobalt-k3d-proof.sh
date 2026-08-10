#!/usr/bin/env bash
set -euo pipefail

# Node-owned command-runner contract for the authorized cobalt k3d integration
# proof. The fleet command runner invokes this script inside the sealed fixture
# with RESULT_DIR exported to an absolute, per-shard durable evidence root; the
# accepted shared command helper guarantees that export. We make that runtime
# contract explicit and self-describing here so a runner that omits the result
# root fails with a clear message instead of an opaque `unbound variable`.
#
# RB-243 attribution: the previous campaign's ad-hoc verbatim wrapper read
# `$RESULT_DIR` under `set -u` with no guard, so when the (now-repaired) helper
# did not export RESULT_DIR the proof died at its third line before any product
# work. The defect was shared, not a cobalt product verdict; the chart, values,
# and `cobalt-k3d.sh` bytes were correct. This wrapper gives the node ownership
# of the result-root runtime contract, and scripts/validate/cobalt-k3d-contract.sh
# regression-tests the explicit refusal on an omitted or relative result root.
#
# cobalt-k3d.sh owns cluster/registry creation, path isolation, and teardown
# (its own EXIT trap deletes the marker-owned cluster). This wrapper only pins
# the mandatory path-isolation flag and the absolute durable package path, tees
# the combined log, and hashes the durable evidence.

result_dir="${RESULT_DIR:?must be exported by the command runner to an absolute durable evidence root}"
case "${result_dir}" in
/*) ;;
*)
  echo "❌ RESULT_DIR must be an absolute path (command-runner contract); got '${result_dir}'" >&2
  exit 1
  ;;
esac

evidence_dir="${result_dir}/evidence"
log="${evidence_dir}/cobalt-k3d.log"
package="${evidence_dir}/diene-cobalt-0.1.0.tgz"
hashes="${evidence_dir}/cobalt-k3d.sha256"
hashes_tmp="${evidence_dir}/cobalt-k3d.sha256.tmp"

# Best-effort durable evidence retention on any exit, including failures.
hash_evidence() {
  rc=$?
  : >"${hashes_tmp}"
  [ ! -s "${log}" ] || sha256sum "${log}" >>"${hashes_tmp}"
  [ ! -s "${package}" ] || sha256sum "${package}" >>"${hashes_tmp}"
  [ ! -s "${hashes_tmp}" ] || mv "${hashes_tmp}" "${hashes}"
  exit "${rc}"
}
trap hash_evidence EXIT

mkdir -p "${evidence_dir}"
for artifact in "${log}" "${package}" "${hashes}"; do
  [ ! -e "${artifact}" ] || {
    echo "❌ refusing to overwrite pre-existing evidence artifact ${artifact}" >&2
    exit 1
  }
done

export K3D_ISOLATE_BY_PATH=true
COBALT_K3D_PACKAGE_PATH="${package}" bash ./scripts/validate/cobalt-k3d.sh 2>&1 | tee "${log}"

test -s "${log}"
test -s "${package}"
rg -q "k3d lapras install, ESO pod health, store applied, and local OCI round-trip passed" "${log}"
sha256sum "${log}" "${package}" >"${hashes}"
test "$(wc -l <"${hashes}")" -eq 2

echo "✅ cobalt k3d proof evidence captured under ${evidence_dir}"
