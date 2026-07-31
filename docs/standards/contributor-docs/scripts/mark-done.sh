#!/usr/bin/env bash
# Usage: mark-done.sh <state-file> <filename>
# Moves filename from pendingFiles to processedFiles.
#
# Refuses a filename that was never queued. A typo or a stale completion must not
# silently append an unknown path to processedFiles -- that corrupts resumable
# state in a way the next run cannot detect.
set -euo pipefail

STATE_FILE="$1"
FILENAME="$2"

# Precondition, evaluated before anything is written: the filename must be known
# to this state file, either still pending or already processed. jq -e sets a
# non-zero exit for a false/null result, which is what gates the write.
if ! jq -e --arg f "$FILENAME" \
  '(.filesToProcess // []) | index($f) != null' \
  "$STATE_FILE" >/dev/null; then
  echo "❌ '${FILENAME}' was never queued in ${STATE_FILE}" >&2
  exit 1
fi

# Already processed: nothing to do. Return success so a retried batch is
# idempotent, and leave the file untouched rather than rewriting it.
if jq -e --arg f "$FILENAME" '.processedFiles | index($f) != null' "$STATE_FILE" >/dev/null; then
  echo "✅ '${FILENAME}' already marked done"
  exit 0
fi

TEMP=$(mktemp "${STATE_FILE}.XXXXXX")
trap 'rm -f "${TEMP}"' EXIT
jq --arg f "$FILENAME" \
  '.pendingFiles -= [$f] | .processedFiles += [$f] | .processedFiles |= unique' \
  "$STATE_FILE" >"$TEMP"
mv "$TEMP" "$STATE_FILE"
trap - EXIT
