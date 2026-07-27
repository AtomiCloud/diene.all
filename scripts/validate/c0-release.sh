#!/usr/bin/env bash
# Reusable NEUTRAL-RELEASE digest-compare gate for downstream C0 consumers.
# Host-safe: pure bash + jq + sha256sum + git. NO pub resolution, NO network.
# Authenticates that the merged contracts/c0/ tree IS the pinned release
# byte-for-byte and fails closed on any drift.
#
# RECOVERED under R-E1a from the preserved C0-migration worktree
# (.worktrees/dart-api-c0mig-mrv4vyux, branch diene-cond-5b1b11-api@7c1969a),
# byte-preserved since 2026-07-21 at sha256
# 21d57c8dff2ed5673c0f98816623f9f2233ed179fffa32eab792fec4e0628b12.
#
# TWO SUBSTANTIVE CHANGES from the preserved bytes, both re-derived by
# measurement rather than carried forward on trust:
#
#  1. THE PINS ADVANCED r1 -> r2. The preserved script pinned releaseId
#     `c0-fixtures-r1`, digest eda331ec…, commit 6e65748, and asserted
#     `domains == ["config","problem"]`. The set frozen across the accepted dart
#     family is now `c0-fixtures-r2` (digest 0e64439c…, contractVersion 2,
#     domains config+identity+problem+result-wire). Verified present-tense
#     against all six accepted siblings: result, interfaces, core-utils, config
#     and problems each carry the complete 17-file r2 set, byte-identical to one
#     another on all 17 blobs. Crucially `cases/problem.json` is BYTE-IDENTICAL
#     between r1 and r2, so the recovered projection and its expected portal
#     segments remain correct under r2 — the recovery is a genuine carry-forward,
#     not a rewrite.
#     (auth-engine carries only 15 of the 17 and its own SHA256SUMS therefore
#     cannot verify there; reported to the lead inbox, not fixed from here.)
#
#  2. THE ANCESTRY CHECK IS A BLOB CHECK NOW. The preserved script ran
#     `git merge-base --is-ancestor "${PINNED_RELEASE_COMMIT}" HEAD`. Hops in
#     this cascade land as SQUASH merges, so the release commit is NOT an
#     ancestor of any accepted dart head even where the content is present —
#     measured: 6e65748 is not an ancestor of dart-lib, of this branch, or of
#     auth-engine, while five siblings carry the bytes. The ancestry test is a
#     guaranteed FALSE NEGATIVE on a squashed hop, so arrival is tested by
#     COMPARING THE BLOB, which is what actually establishes the content is here.
set -euo pipefail

PINNED_RELEASE_ID='c0-fixtures-r2'
PINNED_RELEASE_DIGEST='0e64439c681a22fb4f02285c082ed8ffb7b465e732fde4e49757e9e3c9a5783e'
PINNED_CONTRACT_VERSION=2
PINNED_DOMAINS='["config","identity","problem","result-wire"]'
# The §2 problem case is the ONLY release case this package projects from, so its
# blob is pinned directly: a re-cut release that changed it would redden here
# even if the manifest digest were regenerated consistently.
PINNED_PROBLEM_CASE_SHA256='a8c02554c198627df9badc6c2377218556ec8bd3a0b1edcdb20aedeebe43f988'

root_dir="$(git rev-parse --show-toplevel)"
cd "${root_dir}"

c0="${1:-contracts/c0}"
manifest="${c0}/RELEASE.json"
sums="${c0}/SHA256SUMS"

for f in "${manifest}" "${sums}"; do
  [ -f "${f}" ] || {
    echo "❌ missing required release file: ${f}" >&2
    exit 1
  }
done

echo '→ manifest is compact-canonical'
jq -cS . "${manifest}" | cmp - "${manifest}"

echo "→ contract version is ${PINNED_CONTRACT_VERSION}"
test "$(jq -r .contractVersion "${manifest}")" = "${PINNED_CONTRACT_VERSION}"

echo '→ domains are exactly the r2 coverage set'
test "$(jq -c .domains "${manifest}")" = "${PINNED_DOMAINS}"

echo '→ SHA256SUMS authenticate every release file'
# The checker's OWN rc, taken directly. Piping this into `tail`/`grep` would
# report the pipe's status instead and a real corruption would read as green.
sums_log="$(mktemp)"
rc=0
(cd "${c0}" && sha256sum -c SHA256SUMS) >"${sums_log}" 2>&1 || rc=$?
rows="$(wc -l <"${sums}")"
ok="$(grep -c ': OK$' "${sums_log}" || true)"
bad="$(grep -c ': FAILED' "${sums_log}" || true)"
echo "   ${rows} rows, ${ok} OK, ${bad} FAILED (rc=${rc})"
if [ "${rc}" -ne 0 ] || [ "${ok}" -ne "${rows}" ] || [ "${bad}" -ne 0 ]; then
  cat "${sums_log}" >&2
  rm -f "${sums_log}"
  echo "❌ release files do not authenticate against SHA256SUMS" >&2
  exit 1
fi
rm -f "${sums_log}"
# A manifest must never hash ITSELF: a self-entry can never verify again once a
# row is appended, and the resulting FAILED reads exactly like real corruption.
test "$(grep -c 'SHA256SUMS' "${sums}" || true)" -eq 0

echo '→ complete-release digest == recorded == pinned'
actual="$({
  printf 'atomicloud.diene.c0-fixtures.release.v1\n'
  jq -cS 'del(.releaseDigest)' "${manifest}"
  cat "${sums}"
} | sha256sum | cut -d' ' -f1)"
recorded="$(jq -r .releaseDigest "${manifest}")"
echo "   actual=${actual}"
echo "   recorded=${recorded}"
test "${actual}" = "${recorded}"
test "${actual}" = "${PINNED_RELEASE_DIGEST}"
test "$(jq -r .releaseId "${manifest}")" = "${PINNED_RELEASE_ID}"

echo '→ the projected-from case blob is the pinned one'
case_sha="$(sha256sum "${c0}/cases/problem.json" | cut -d' ' -f1)"
echo "   cases/problem.json=${case_sha}"
test "${case_sha}" = "${PINNED_PROBLEM_CASE_SHA256}"

echo '→ .prettierignore matches RELEASE.json formatterPolicy.sha256'
# NEW ASSERTION, not inherited. RELEASE.json pins the digest of the root
# .prettierignore that keeps the formatter off the release cases, but nothing in
# this repo verified that pin — measured with `grep -rln formatterPolicy` over
# scripts/, probes/ and nix/: zero enforcing call sites. An unenforced pin is
# documentation wearing a gate's clothes; it cannot tell you when the thing it
# describes drifts. Asserted here so a reformatted or edited .prettierignore
# reddens instead of silently unprotecting contracts/c0.
policy_pin="$(jq -r '.formatterPolicy.sha256' "${manifest}")"
policy_path="$(jq -r '.formatterPolicy.path' "${manifest}")"
[ -f "${policy_path}" ] || {
  echo "❌ formatterPolicy.path does not exist: ${policy_path}" >&2
  exit 1
}
policy_sha="$(sha256sum "${policy_path}" | cut -d' ' -f1)"
echo "   ${policy_path}=${policy_sha}"
echo "   pinned            =${policy_pin}"
test "${policy_sha}" = "${policy_pin}"
# Both directions: the file must also actually EXCLUDE every path the policy
# names, so a same-digest file that had never listed them could not pass.
missing_excludes=0
while IFS= read -r p; do
  grep -qxF "${p}" "${policy_path}" || {
    echo "   NOT EXCLUDED: ${p}" >&2
    missing_excludes=$((missing_excludes + 1))
  }
done < <(jq -r '.formatterPolicy.prettierExcludedPaths[]' "${manifest}")
echo "   policy paths not excluded: ${missing_excludes} (must be 0)"
test "${missing_excludes}" -eq 0

echo "✅ digest-compare gate PASS: ${PINNED_RELEASE_ID} (${PINNED_RELEASE_DIGEST})"

echo '→ regenerating the downstream projection and comparing every byte'
bash scripts/validate/gen-c0-projection.sh --check

echo '→ projected fixtures self-authenticate'
fx='packages/diene_e2e/test/fixtures/c0'
frc=0
(cd "${fx}" && sha256sum -c SHA256SUMS) >/dev/null 2>&1 || frc=$?
frows="$(wc -l <"${fx}/SHA256SUMS")"
echo "   ${frows} projected fixture rows (rc=${frc})"
test "${frc}" -eq 0
test "${frows}" -ge 1

echo '✅ downstream C0 digest-compare gate PASS (diene_e2e)'
