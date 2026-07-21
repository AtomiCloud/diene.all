#!/usr/bin/env bash
set -euo pipefail

mode="${1:-}"
report="${2:-}"
threshold="${3:-90}"

[ -z "${mode}" ] && echo "❌ coverage mode not set" >&2 && exit 1
[ ! -s "${report}" ] && echo "❌ ${mode} LCOV report is empty" >&2 && exit 1

percentage="$({
  awk -F: '
    /^LF:/ { found += $2 }
    /^LH:/ { hit += $2 }
    END {
      if (found == 0) exit 2
      printf "%.2f", (hit * 100) / found
    }
  ' "${report}"
} || true)"

[ -z "${percentage}" ] && echo "❌ ${mode} LCOV has no source lines" >&2 && exit 1

awk -v actual="${percentage}" -v minimum="${threshold}" 'BEGIN { exit !(actual + 0 >= minimum + 0) }' || {
  echo "❌ ${mode} coverage ${percentage}% is below ${threshold}%" >&2
  exit 1
}

echo "✅ ${mode} coverage ${percentage}% meets ${threshold}%"
