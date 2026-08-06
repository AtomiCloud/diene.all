#!/usr/bin/env bash
set -euo pipefail

# Every ROOT nixpkgs input must pin an exact commit; transitive inputs may float.
# Resolve via .nodes.root.inputs, never .nodes by declared name — transitive deps
# carry the bare names, and reading them checks someone else's pin as ours.

lock="flake.lock"
declaration="flake.nix"

[ -f "${lock}" ] || {
  echo "❌ nixpkgs-pin: ${lock} is absent, so no pin can be checked" >&2
  exit 1
}
[ -f "${declaration}" ] || {
  echo "❌ nixpkgs-pin: ${declaration} is absent, so no pin can be checked" >&2
  exit 1
}

mapfile -t nodes < <(jq -r '.nodes.root.inputs | to_entries[] | select(.key | test("nixpkgs")) | .value' "${lock}")

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

  # original vs locked can disagree: an exact request whose resolution moved.
  if [ "${locked_rev}" != "${original_rev}" ]; then
    echo "❌ nixpkgs-pin: root input '${node}' asks for ${original_rev} but is locked to ${locked_rev}" >&2
    failed=1
  fi
done

# Catch a declaration edited without re-locking: every rev flake.nix names must be in force.
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
