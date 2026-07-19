#!/usr/bin/env bash
# Q-G22 — cert-manager sequential-minor upgrade gate.
#
# cert-manager is pinned on a sequential-minor upgrade ladder from the fleet
# baseline v1.15: a version bump may advance at most ONE minor at a time (no
# version-skip), and never change the major. The CRD upgrade path rides the same
# ladder because the CRDs ship inside the cert-manager chart. This gate is the
# chart repo's OWN CI check (Q-G22): a version-bump PR that skips a minor goes
# red here, nothing fleet-side.
#
# Usage:
#   sequential-minor.sh <from-version> <to-version>
#       Exit 0 iff the major is unchanged and (to.minor - from.minor) is 0 or +1.
#   sequential-minor.sh --pin <chart-dir>
#       Read the cert-manager pin from <chart-dir>/Chart.yaml. When the env var
#       SULFUR_PREV_VERSION (the base-branch pin supplied by CI) is set, gate the
#       bump SULFUR_PREV_VERSION -> pin; otherwise only assert the pin is a
#       stable vX.Y.Z.
set -euo pipefail

major_of() {
  local v="${1#v}"
  echo "${v%%.*}"
}

minor_of() {
  local v="${1#v}"
  local rest="${v#*.}"
  echo "${rest%%.*}"
}

check_step() {
  local from="$1"
  local to="$2"
  local from_major from_minor to_major to_minor delta
  from_major="$(major_of "$from")"
  to_major="$(major_of "$to")"
  from_minor="$(minor_of "$from")"
  to_minor="$(minor_of "$to")"
  if [ "$from_major" != "$to_major" ]; then
    echo "❌ major version skip ${from} → ${to}" >&2
    return 1
  fi
  delta=$((to_minor - from_minor))
  if [ "$delta" -lt 0 ]; then
    echo "❌ minor downgrade ${from} → ${to}" >&2
    return 1
  fi
  if [ "$delta" -gt 1 ]; then
    echo "❌ minor version skip ${from} → ${to} (sequential-minor only, Q-G22)" >&2
    return 1
  fi
  echo "✅ sequential-minor step ${from} → ${to}"
}

if [ "${1:-}" = "--pin" ]; then
  chart_dir="${2:?chart directory required}"
  pin="$(yq -r '.dependencies[] | select(.name == "cert-manager") | .version' "${chart_dir}/Chart.yaml")"
  if [ -z "$pin" ]; then
    echo "❌ cert-manager dependency not found in ${chart_dir}/Chart.yaml" >&2
    exit 1
  fi
  if [[ ! $pin =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "❌ cert-manager pin '${pin}' is not a stable vX.Y.Z" >&2
    exit 1
  fi
  if [ -n "${SULFUR_PREV_VERSION:-}" ]; then
    check_step "$SULFUR_PREV_VERSION" "$pin"
  else
    echo "✅ cert-manager pin ${pin} is stable semver (set SULFUR_PREV_VERSION to gate the bump)"
  fi
  exit 0
fi

from="${1:?from version required (or: --pin <chart-dir>)}"
to="${2:?to version required}"
check_step "$from" "$to"
