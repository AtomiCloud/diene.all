#!/usr/bin/env bash
# Usage: next-file.sh <state-file> [--batch N]
# Prints next pending file(s), one per line. Empty output if none remain.
#
# Every argument is validated before jq runs, and the batch size is handed to jq
# as typed JSON through --argjson instead of being interpolated into the filter.
# An interpolated batch would let a crafted value close the slice and append its
# own jq program text, so the filter below must stay a fixed single-quoted string.
set -euo pipefail

next_file_refuse() {
  echo "❌ Usage: next-file.sh <state-file> [--batch N]" >&2
  exit 1
}

next_file_main() {
  local state_file batch=1 pending

  [[ $# -ge 1 ]] || next_file_refuse
  state_file=$1
  shift
  # An option-shaped state path would be consumed by jq as a flag rather than a
  # file operand, so it is refused here instead of reaching the reader.
  [[ -n $state_file && $state_file != -* ]] || next_file_refuse

  while [[ $# -gt 0 ]]; do
    case "$1" in
    --batch)
      [[ $# -ge 2 ]] || next_file_refuse
      batch=$2
      shift 2
      ;;
    *)
      next_file_refuse
      ;;
    esac
  done
  [[ $batch =~ ^[1-9][0-9]*$ ]] || next_file_refuse

  pending=$(jq -r --argjson batch "$batch" '.pendingFiles[:$batch][]' "$state_file")
  if [[ -n $pending ]]; then
    printf '%s\n' "$pending"
  fi
}

next_file_main "$@"
