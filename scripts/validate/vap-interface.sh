#!/usr/bin/env bash
set -euo pipefail

lock="${VAP_INTERFACE_LOCK:-policies/vap-interface.json}"

jq -e '
  .schema == "helm-wrapper.vap-interface.v1" and
  .ownerNode == "charts/vap-policies" and
  (.sourceArtifactCommit | test("^[0-9a-f]{40}$")) and
  (.ratchetAcceptanceAtBuild | IN("unaccepted", "accepted")) and
  (.definitions | length > 0)
' "${lock}" >/dev/null

expected_files="$(mktemp)"
actual_files="$(mktemp)"
trap 'rm -f "${expected_files}" "${actual_files}"' EXIT

jq -r '.definitions[].path | sub("^policies/vap/"; "")' "${lock}" | sort >"${expected_files}"
find policies/vap -maxdepth 1 -type f -name '*.yaml' -exec basename {} \; | sort >"${actual_files}"
cmp "${expected_files}" "${actual_files}"

# Hash with coreutils rather than `nix hash file` so the lock stays verifiable in any
# venue that carries the CI toolchain without Nix.
while IFS=$'\t' read -r path expected; do
  actual="$(sha256sum "${path}" | awk '{ print $1 }')"
  if [ "${actual}" != "${expected}" ]; then
    echo "❌ VAP interface drift: ${path} expected ${expected}, got ${actual}" >&2
    exit 1
  fi
done < <(jq -r '.definitions[] | [.path, .sha256] | @tsv' "${lock}")

echo "✅ Borrowed VAP definitions match the pinned interface lock"
