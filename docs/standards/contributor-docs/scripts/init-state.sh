#!/usr/bin/env bash
# Usage: <file-list> | init-state.sh <state-file> <source-paths-json> <concurrent> <output-dir>
# Reads file list from stdin, one file per line.
set -euo pipefail

STATE_FILE="$1"
SOURCE_PATHS="$2"
CONCURRENT="$3"
OUTPUT_DIR="$4"

FILES_JSON=$(jq -R -s 'split("\n") | map(select(. != ""))')

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
  }' >"$STATE_FILE"

echo "Initialized with $(echo "$FILES_JSON" | jq length) files"
