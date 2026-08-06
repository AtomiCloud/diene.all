#!/usr/bin/env bash
set -euo pipefail

# flake.nix states the rule and, until this script, nothing enforced it: every nixpkgs
# input this repository declares is pinned to an EXACT COMMIT, never to a channel name.
# The comment above those lines says so and adds that nothing validates it, which was
# accurate.
#
# BOUNDARY. This guards the ROOT's nixpkgs inputs and nothing else. It is silent about
# the transitive closure, where other flakes' own nixpkgs inputs float on channels
# legitimately and are none of this repository's business.
#
# ⚠ RESOLUTION GOES THROUGH `.nodes.root.inputs`, NEVER THROUGH `.nodes` BY DECLARED
# NAME. That distinction is the entire reason this script is careful: flake.lock carries
# transitive dependencies' nixpkgs under the bare names `nixpkgs-2605` and
# `nixpkgs-unstable`, while the root's own inputs are the `_2`-suffixed nodes. An audit
# that read the lock by name compared this repository's declaration against somebody
# else's input, found a channel ref, and reported the rule broken when it was in force.
# A guard that reproduced that lookup would be worse than no guard: it would be loud and
# wrong.

lock="flake.lock"
declaration="flake.nix"
snapshot="nix/snapshots/nixpkgs.json"

[ -f "${lock}" ] || {
  echo "❌ nixpkgs-pin: ${lock} is absent, so no pin can be checked" >&2
  exit 1
}
[ -f "${declaration}" ] || {
  echo "❌ nixpkgs-pin: ${declaration} is absent, so no pin can be checked" >&2
  exit 1
}
[ -f "${snapshot}" ] || {
  echo "❌ nixpkgs-pin: ${snapshot} is absent, so no pin can be checked" >&2
  exit 1
}

snapshot_rev="$(jq -r '.rev // ""' "${snapshot}")"
if ! printf '%s' "${snapshot_rev}" | grep -Eq '^[0-9a-f]{40}$'; then
  echo "❌ nixpkgs-pin: ${snapshot} does not declare an exact 40-character commit" >&2
  exit 1
fi

if ! grep -Fq "nixpkgs-2605.url = \"github:NixOS/nixpkgs/${snapshot_rev}\";" "${declaration}"; then
  echo "❌ flake.nix does not use the authoritative nixpkgs SHA" >&2
  exit 1
fi

mapfile -t nodes < <(jq -r '.nodes.root.inputs | to_entries[] | select(.key | test("nixpkgs")) | .value' "${lock}")

# A check that inspects nothing is not a pass. If the root declares no nixpkgs input at
# all the assumption behind this script has changed and it must be re-read, not skipped.
if [ "${#nodes[@]}" -eq 0 ]; then
  echo "❌ nixpkgs-pin: the root declares no nixpkgs input, so this guard inspected nothing" >&2
  exit 1
fi

failed=0

for node in "${nodes[@]}"; do
  ref="$(jq -r --arg n "${node}" '.nodes[$n].original.ref // ""' "${lock}")"
  original_rev="$(jq -r --arg n "${node}" '.nodes[$n].original.rev // ""' "${lock}")"
  locked_rev="$(jq -r --arg n "${node}" '.nodes[$n].locked.rev // ""' "${lock}")"

  if [ -n "${ref}" ]; then
    echo "❌ nixpkgs-pin: root input '${node}' follows the channel '${ref}' instead of an exact commit" >&2
    failed=1
    continue
  fi

  if ! printf '%s' "${original_rev}" | grep -Eq '^[0-9a-f]{40}$'; then
    echo "❌ nixpkgs-pin: root input '${node}' declares '${original_rev}', which is not an exact 40-character commit" >&2
    failed=1
    continue
  fi

  # The lock records what was asked for and what was resolved separately, so a lock can
  # be internally dishonest: an exact request whose resolution moved elsewhere.
  if [ "${locked_rev}" != "${original_rev}" ]; then
    echo "❌ nixpkgs-pin: root input '${node}' asks for ${original_rev} but is locked to ${locked_rev}" >&2
    failed=1
  fi
done

# The lock alone cannot catch a declaration edited without re-locking: `original` would
# still carry the previous commit and agree with `locked`. So every commit flake.nix
# names for a nixpkgs input must actually be in force.
while read -r declared; do
  [ -n "${declared}" ] || continue
  if ! jq -e --arg r "${declared}" '[.nodes.root.inputs | to_entries[] | select(.key | test("nixpkgs")) | .value] as $roots
        | [.nodes | to_entries[] | select(.key as $k | $roots | index($k)) | .value.locked.rev]
        | index($r)' "${lock}" >/dev/null; then
    echo "❌ nixpkgs-pin: ${declaration} declares ${declared} but no root nixpkgs input is locked to it" >&2
    failed=1
  fi
done < <(grep -E 'nixpkgs[A-Za-z0-9_-]*\.url' "${declaration}" | grep -oE '[0-9a-f]{40}')

if [ "${failed}" -ne 0 ]; then
  exit 1
fi

echo "ℹ️ root nixpkgs inputs inspected: ${#nodes[@]}"
echo "✅ Every declared nixpkgs input is pinned to an exact commit"
