#!/usr/bin/env bash
# Usage: <file-list> | init-state.sh <state-file> <source-paths-json> <concurrent> <output-dir>
#        init-state.sh --check-write-contract
# Reads file list from stdin, one file per line.
#
# Feed the list with printf, never echo: `echo "a.mdx\nb.mdx"` emits a literal
# backslash-n in Bash and records one filename instead of two.
#   printf '%s\n' a.mdx b.mdx | init-state.sh ...
set -euo pipefail

if [[ ${1:-} == "--check-write-contract" ]]; then
  REPO_ROOT=$(git rev-parse --show-toplevel)
  CD_ROOT="$REPO_ROOT/docs/standards/contributor-docs"
  WRITE_PHASE="$CD_ROOT/write/PHASE.md"
  WRITE_AGENT="$CD_ROOT/write/state-agent.md"
  CONTROL_DIR=$(mktemp -d)
  trap 'rm -rf -- "${CONTROL_DIR}"' EXIT
  FAILURES=0

  MARKERS=(
    write-state-schema
    write-provenance-record
    write-approval-record
    write-collision-record
    write-audit-repair-record
    gap-transition-record
  )
  for MARKER in "${MARKERS[@]}"; do
    awk -v marker="canonical-block: $MARKER" '
      index($0, marker) { marked=1; next }
      marked && /^[[:space:]]*```json[[:space:]]*$/ { inside=1; next }
      inside && /^[[:space:]]*```[[:space:]]*$/ { exit }
      inside { sub(/^[[:space:]]{0,3}/, ""); print }
    ' "$WRITE_PHASE" >"$CONTROL_DIR/phase-$MARKER.json"
    awk -v marker="canonical-block: $MARKER" '
      index($0, marker) { marked=1; next }
      marked && /^[[:space:]]*```json[[:space:]]*$/ { inside=1; next }
      inside && /^[[:space:]]*```[[:space:]]*$/ { exit }
      inside { sub(/^[[:space:]]{0,3}/, ""); print }
    ' "$WRITE_AGENT" >"$CONTROL_DIR/agent-$MARKER.json"
    jq -ceS '[paths as $p | (getpath($p) | type) as $t | select($t != "array" and $t != "object") | {path:$p,type:$t}]' \
      "$CONTROL_DIR/phase-$MARKER.json" >"$CONTROL_DIR/phase-$MARKER.canonical"
    jq -ceS '[paths as $p | (getpath($p) | type) as $t | select($t != "array" and $t != "object") | {path:$p,type:$t}]' \
      "$CONTROL_DIR/agent-$MARKER.json" >"$CONTROL_DIR/agent-$MARKER.canonical"
    if ! cmp -s "$CONTROL_DIR/phase-$MARKER.canonical" "$CONTROL_DIR/agent-$MARKER.canonical"; then
      echo "❌ Canonical block drift: $MARKER" >&2
      FAILURES=$((FAILURES + 1))
    fi
  done

  jq -r '.step' "$CONTROL_DIR/phase-write-state-schema.json" |
    tr '|' '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' |
    LC_ALL=C sort -u >"$CONTROL_DIR/steps"
  awk '/^## State Machine$/ { inside=1; next } inside && /^## / { exit } inside' \
    "$WRITE_PHASE" >"$CONTROL_DIR/machine"
  awk '/^## Step Dispatch$/ { inside=1; next } inside && /^### Gap Sub-Dispatch$/ { exit } inside' \
    "$WRITE_PHASE" >"$CONTROL_DIR/dispatch"
  while IFS= read -r STEP; do
    if ! grep -Fq "[$STEP]" "$CONTROL_DIR/machine"; then
      echo "❌ State-machine omission: $STEP" >&2
      FAILURES=$((FAILURES + 1))
    fi
    if ! grep -Fq "| \`$STEP\`" "$CONTROL_DIR/dispatch"; then
      echo "❌ Step-dispatch omission: $STEP" >&2
      FAILURES=$((FAILURES + 1))
    fi
  done <"$CONTROL_DIR/steps"
  # Backticks in this single-quoted pattern are literal Markdown delimiters.
  # shellcheck disable=SC2016
  STEP_COUNT=$(grep -c '^| `[^`]*`' "$CONTROL_DIR/dispatch")
  if [[ $STEP_COUNT -ne 10 ]]; then
    echo "❌ Step Dispatch has $STEP_COUNT step rows, expected 10" >&2
    FAILURES=$((FAILURES + 1))
  fi

  RETIRED_TIERS='completed''Tiers'
  RETIRED_ERRORS='"''errors''"[[:space:]]*:'
  if git -C "$REPO_ROOT" grep -En "$RETIRED_TIERS|$RETIRED_ERRORS" -- \
    docs/standards/contributor-docs; then
    echo "❌ Retired write-state field survives" >&2
    FAILURES=$((FAILURES + 1))
  fi
  MECHANISM_MARKER='canonical-block: gap-transition-''mechanism'
  MECHANISM_COUNT=$(git -C "$REPO_ROOT" grep -lF "$MECHANISM_MARKER" -- \
    docs/standards/contributor-docs | wc -l | tr -d ' ')
  if [[ $MECHANISM_COUNT -ne 1 ]]; then
    echo "❌ Gap mechanism copies: $MECHANISM_COUNT" >&2
    FAILURES=$((FAILURES + 1))
  fi

  cat >"$CONTROL_DIR/reducer.jq" <<'JQ'
def refuse($code): error($code);
def next_gap($status):
  {enqueued:"planned", planned:"prepared", prepared:"scaffolded",
   scaffolded:"reset", reset:"cleaned", cleaned:"cleared"}[$status];
def apply($state; $operation; $data):
  if $operation == "create-scaffold" then
    if $state.step != "scaffold_prepared" then refuse("SCAFFOLD_NOT_PREPARED")
    else $state end
  elif $operation == "prepare-scaffold" then
    if $state.step != "scaffold" then refuse("WRITE_TRANSITION_INVALID")
    else $state | .step = "scaffold_prepared" end
  elif $operation == "finalize-scaffold" then
    if $state.step != "scaffold_prepared" then refuse("WRITE_TRANSITION_INVALID")
    else $state | .step = "write_tier_1" end
  elif $operation == "complete-tier" then
    if ($state.pending | length) != 0 then refuse("WRITE_INCOMPLETE")
    else $state | .step = "completed" end
  elif $operation == "record-write" then
    if $data.returnedHash != $data.diskHash then refuse("WRITE_HASH_MISMATCH")
    else $state end
  elif $operation == "gap-advance" then
    if next_gap($state.gapStatus) != $data.target then refuse("GAP_TRANSITION_INVALID")
    elif $data.target == "prepared" and (($data.expectedScaffold | keys | sort) != ($data.gapPaths | sort))
      then refuse("GAP_MANIFEST_INVALID")
    elif $data.target == "cleaned" and (($data.cleanedTiers | sort) != ($data.resetTiers | sort))
      then refuse("GAP_CLEANUP_INCOMPLETE")
    elif $data.target == "cleared" then $state | .gapStatus = null
    else $state | .gapStatus = $data.target end
  else refuse("UNKNOWN_OPERATION") end;
apply($state; $operation; $data)
JQ

  BASE_STATE='{"step":"scaffold","pending":[],"gapStatus":null}'
  if OUTPUT=$(jq -n -L "$CONTROL_DIR" --argjson state "$BASE_STATE" \
    --arg operation create-scaffold --argjson data '{}' -f "$CONTROL_DIR/reducer.jq" 2>&1); then
    echo "❌ Create-before-prepare control passed" >&2
    FAILURES=$((FAILURES + 1))
  elif [[ $OUTPUT != *SCAFFOLD_NOT_PREPARED* ]]; then
    echo "❌ Create-before-prepare failed for the wrong reason" >&2
    FAILURES=$((FAILURES + 1))
  fi
  if OUTPUT=$(jq -n -L "$CONTROL_DIR" \
    --argjson state '{"step":"write_tier_6","pending":["docs/a.mdx"],"gapStatus":null}' \
    --arg operation complete-tier --argjson data '{}' -f "$CONTROL_DIR/reducer.jq" 2>&1); then
    echo "❌ Pending-completion control passed" >&2
    FAILURES=$((FAILURES + 1))
  elif [[ $OUTPUT != *WRITE_INCOMPLETE* ]]; then
    echo "❌ Pending-completion failed for the wrong reason" >&2
    FAILURES=$((FAILURES + 1))
  fi
  if OUTPUT=$(jq -n -L "$CONTROL_DIR" \
    --argjson state '{"step":"write_tier_2","pending":[],"gapStatus":"enqueued"}' \
    --arg operation gap-advance --argjson data '{"target":"prepared"}' \
    -f "$CONTROL_DIR/reducer.jq" 2>&1); then
    echo "❌ Skipped-gap-status control passed" >&2
    FAILURES=$((FAILURES + 1))
  elif [[ $OUTPUT != *GAP_TRANSITION_INVALID* ]]; then
    echo "❌ Skipped-gap-status failed for the wrong reason" >&2
    FAILURES=$((FAILURES + 1))
  fi
  if OUTPUT=$(jq -n -L "$CONTROL_DIR" \
    --argjson state '{"step":"write_tier_2","pending":[],"gapStatus":"planned"}' \
    --arg operation gap-advance \
    --argjson data '{"target":"prepared","gapPaths":["docs/a.mdx"],"expectedScaffold":{}}' \
    -f "$CONTROL_DIR/reducer.jq" 2>&1); then
    echo "❌ Incomplete-gap-manifest control passed" >&2
    FAILURES=$((FAILURES + 1))
  elif [[ $OUTPUT != *GAP_MANIFEST_INVALID* ]]; then
    echo "❌ Incomplete-gap-manifest failed for the wrong reason" >&2
    FAILURES=$((FAILURES + 1))
  fi
  if OUTPUT=$(jq -n -L "$CONTROL_DIR" \
    --argjson state '{"step":"write_tier_2","pending":[],"gapStatus":"reset"}' \
    --arg operation gap-advance \
    --argjson data '{"target":"cleaned","resetTiers":[2,4],"cleanedTiers":[2]}' \
    -f "$CONTROL_DIR/reducer.jq" 2>&1); then
    echo "❌ Fabricated-cleanup control passed" >&2
    FAILURES=$((FAILURES + 1))
  elif [[ $OUTPUT != *GAP_CLEANUP_INCOMPLETE* ]]; then
    echo "❌ Fabricated-cleanup failed for the wrong reason" >&2
    FAILURES=$((FAILURES + 1))
  fi
  if OUTPUT=$(jq -n -L "$CONTROL_DIR" \
    --argjson state '{"step":"write_tier_2","pending":["docs/a.mdx"],"gapStatus":null}' \
    --arg operation record-write \
    --argjson data '{"returnedHash":"aa","diskHash":"bb"}' \
    -f "$CONTROL_DIR/reducer.jq" 2>&1); then
    echo "❌ Writer-hash-mismatch control passed" >&2
    FAILURES=$((FAILURES + 1))
  elif [[ $OUTPUT != *WRITE_HASH_MISMATCH* ]]; then
    echo "❌ Writer-hash-mismatch failed for the wrong reason" >&2
    FAILURES=$((FAILURES + 1))
  fi

  HEALTHY=$(jq -n -L "$CONTROL_DIR" --argjson state "$BASE_STATE" \
    --arg operation prepare-scaffold --argjson data '{}' -f "$CONTROL_DIR/reducer.jq")
  HEALTHY=$(jq -n -L "$CONTROL_DIR" --argjson state "$HEALTHY" \
    --arg operation finalize-scaffold --argjson data '{}' -f "$CONTROL_DIR/reducer.jq")
  if [[ $(jq -r '.step' <<<"$HEALTHY") != write_tier_1 ]]; then
    echo "❌ Healthy initial scaffold did not reach write_tier_1" >&2
    FAILURES=$((FAILURES + 1))
  fi
  GAP_STATE='{"step":"write_tier_4","pending":[],"gapStatus":"enqueued"}'
  for TARGET in planned prepared scaffolded reset cleaned cleared; do
    DATA=$(jq -cn --arg target "$TARGET" '{target:$target}')
    if [[ $TARGET == prepared ]]; then
      DATA='{"target":"prepared","gapPaths":["docs/a.mdx"],"expectedScaffold":{"docs/a.mdx":"hash"}}'
    elif [[ $TARGET == cleaned ]]; then
      DATA='{"target":"cleaned","resetTiers":[2,4],"cleanedTiers":[2,4]}'
    fi
    GAP_STATE=$(jq -n -L "$CONTROL_DIR" --argjson state "$GAP_STATE" \
      --arg operation gap-advance --argjson data "$DATA" -f "$CONTROL_DIR/reducer.jq")
  done
  if [[ $(jq -r '.gapStatus' <<<"$GAP_STATE") != null ]]; then
    echo "❌ Healthy gap path did not clear" >&2
    FAILURES=$((FAILURES + 1))
  fi

  PLAN_REFERENCE_COUNT=$(git -C "$REPO_ROOT" grep -n 'doc-plan.yaml' -- \
    docs/standards/contributor-docs/write | wc -l | tr -d ' ')
  echo "REVIEW_REQUIRED plan-metadata references=$PLAN_REFERENCE_COUNT; confirm each is metadata-only, never queue membership"

  if [[ $FAILURES -ne 0 ]]; then
    echo "❌ Contributor-doc contract controls failed: $FAILURES" >&2
    exit 1
  fi
  echo "✅ Contributor-doc contract controls passed"
  exit 0
fi

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

echo "✅ Initialized with $(echo "$FILES_JSON" | jq length) files"
