#!/usr/bin/env bash
set -euo pipefail

next_android_build_number() {
  local latest="${1:-0}" run_number="${2:-0}" next
  next="$((latest + 1))"
  [ "${run_number}" -gt "${next}" ] && next="${run_number}"
  printf '%s\n' "${next}"
}
