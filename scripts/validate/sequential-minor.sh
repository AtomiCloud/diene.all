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
#   sequential-minor.sh --ci-gate <chart-dir>
#       The strict CI entrypoint. Reads the candidate pin from
#       <chart-dir>/Chart.yaml and derives the previous pin from the change's base
#       revision (SULFUR_PREV_VERSION > SULFUR_BASE_REF > PR base GITHUB_BASE_REF >
#       push GITHUB_EVENT_BEFORE > local HEAD~1), then gates the bump. It FAILS —
#       rather than falling back to a lax semver check — when the comparison
#       source is unavailable, so a version-skipping bump can never merge green. A
#       base that simply lacks the chart/dependency (newly introduced) passes.
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

read_pin() {
  yq -r '.dependencies[] | select(.name == "cert-manager") | .version' "$1"
}

if [ "${1:-}" = "--ci-gate" ]; then
  chart_dir="${2:?chart directory required}"
  pin="$(read_pin "${chart_dir}/Chart.yaml")"
  if [ -z "$pin" ] || [ "$pin" = "null" ]; then
    echo "❌ cert-manager dependency not found in ${chart_dir}/Chart.yaml" >&2
    exit 1
  fi
  if [[ ! $pin =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "❌ cert-manager pin '${pin}' is not a stable vX.Y.Z" >&2
    exit 1
  fi

  prev="${SULFUR_PREV_VERSION:-}"
  if [ -z "$prev" ]; then
    base_ref=""
    if [ -n "${SULFUR_BASE_REF:-}" ]; then
      if git rev-parse --verify --quiet "${SULFUR_BASE_REF}^{commit}" >/dev/null 2>&1; then
        base_ref="${SULFUR_BASE_REF}"
      else
        echo "❌ Q-G22 base ref '${SULFUR_BASE_REF}' is unavailable — cannot compare the cert-manager pin" >&2
        exit 1
      fi
    elif [ -n "${GITHUB_BASE_REF:-}" ]; then
      for cand in "origin/${GITHUB_BASE_REF}" "refs/remotes/origin/${GITHUB_BASE_REF}" "${GITHUB_BASE_REF}"; do
        if git rev-parse --verify --quiet "${cand}^{commit}" >/dev/null 2>&1; then
          base_ref="$cand"
          break
        fi
      done
      if [ -z "$base_ref" ]; then
        echo "❌ Q-G22 PR base '${GITHUB_BASE_REF}' is unavailable — fetch it (checkout fetch-depth: 0) so the sequential-minor gate can compare the cert-manager pin" >&2
        exit 1
      fi
    elif [ -n "${GITHUB_EVENT_BEFORE:-}" ] && [[ ! ${GITHUB_EVENT_BEFORE} =~ ^0+$ ]]; then
      if git rev-parse --verify --quiet "${GITHUB_EVENT_BEFORE}^{commit}" >/dev/null 2>&1; then
        base_ref="${GITHUB_EVENT_BEFORE}"
      else
        echo "❌ Q-G22 push base '${GITHUB_EVENT_BEFORE}' is unavailable — deepen the checkout so the sequential-minor gate can compare the cert-manager pin" >&2
        exit 1
      fi
    elif git rev-parse --verify --quiet "HEAD~1^{commit}" >/dev/null 2>&1; then
      base_ref="HEAD~1"
    fi

    if [ -z "$base_ref" ]; then
      echo "❌ Q-G22 comparison source unavailable (no SULFUR_PREV_VERSION and no base revision) — cannot prove the sequential-minor gate" >&2
      exit 1
    fi

    base_chart="$(git show "${base_ref}:${chart_dir}/Chart.yaml" 2>/dev/null || true)"
    if [ -z "$base_chart" ]; then
      echo "✅ Q-G22 cert-manager pin ${pin}: base ${base_ref} has no ${chart_dir}/Chart.yaml (chart newly introduced; nothing to compare)"
      exit 0
    fi
    prev="$(printf '%s\n' "$base_chart" | yq -r '.dependencies[] | select(.name == "cert-manager") | .version' 2>/dev/null || true)"
    if [ -z "$prev" ] || [ "$prev" = "null" ]; then
      echo "✅ Q-G22 cert-manager pin ${pin}: base ${base_ref} has no cert-manager dependency (dependency newly introduced; nothing to compare)"
      exit 0
    fi
  fi

  check_step "$prev" "$pin"
  exit 0
fi

if [ "${1:-}" = "--pin" ]; then
  chart_dir="${2:?chart directory required}"
  pin="$(read_pin "${chart_dir}/Chart.yaml")"
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
