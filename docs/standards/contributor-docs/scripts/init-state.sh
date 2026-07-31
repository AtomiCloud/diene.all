#!/usr/bin/env bash
# Usage: <file-list> | init-state.sh <state-file> <source-paths-json> <concurrent> <output-dir>
# Reads file list from stdin, one file per line.
#
# Feed the list with printf, never echo: `echo "a.mdx\nb.mdx"` emits a literal
# backslash-n in Bash and records one filename instead of two.
#   printf '%s\n' a.mdx b.mdx | init-state.sh ...
set -euo pipefail

STATE_FILE="$1"
SOURCE_PATHS="$2"
CONCURRENT="$3"
OUTPUT_DIR="$4"

# Both paths are routinely nested (write-tier and fact-check state live under
# their own subdirectories), so create and validate both parents before writing.
STATE_DIR=$(dirname "$STATE_FILE")
mkdir -p "$STATE_DIR" "$OUTPUT_DIR"
for dir in "$STATE_DIR" "$OUTPUT_DIR"; do
  [ -d "$dir" ] || {
    echo "❌ '${dir}' is not a directory" >&2
    exit 1
  }
  [ -w "$dir" ] || {
    echo "❌ '${dir}' is not writable" >&2
    exit 1
  }
done

FILES_JSON=$(jq -R -s 'split("\n") | map(select(. != ""))')

# Written through a temp file in the destination directory so an interrupted run
# never leaves a half-written state file behind.
TEMP=$(mktemp "${STATE_FILE}.XXXXXX")
trap 'rm -f "${TEMP}"' EXIT
jq -n \
  --argjson sourcePaths "$SOURCE_PATHS" \
  --arg outputDir "$OUTPUT_DIR" \
  --argjson concurrent "$CONCURRENT" \
  --argjson files "$FILES_JSON" \
  --arg startTime "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  '{
    sourcePaths: $sourcePaths,
    outputDir: $outputDir,
    concurrentAgents: $concurrent,
    filesToProcess: $files,
    processedFiles: [],
    pendingFiles: $files,
    startTime: $startTime
  }' >"$TEMP"
mv "$TEMP" "$STATE_FILE"
trap - EXIT

echo "Initialized with $(echo "$FILES_JSON" | jq length) files"
