#!/usr/bin/env bash
# Usage: mark-done.sh <state-file> <filename> --plan-hash <sha256>
# Moves filename from pendingFiles to processedFiles.
#
# Refuses a filename that was never queued. A typo or a stale completion must not
# silently append an unknown path to processedFiles -- that corrupts resumable
# state in a way the next run cannot detect.
set -euo pipefail

[[ $# -eq 4 && $3 == "--plan-hash" && $4 =~ ^[0-9a-f]{64}$ ]] || {
  echo "❌ Usage: mark-done.sh <state-file> <filename> --plan-hash <64-hex>" >&2
  exit 1
}

STATE_FILE="$1"
FILENAME="$2"
PLAN_HASH="$4"
REPO_ROOT=$(git rev-parse --show-toplevel)
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
STATE_FILE_ABS=$(realpath -m -- "$STATE_FILE")

assert_processor_completion_authority() {
  local prefix="$REPO_ROOT/.contributor-docs/write-tier-" suffix="/state.json"
  local tier write_state target_file expected_hash actual_hash

  if [[ $STATE_FILE_ABS != "$prefix"*"$suffix" ]]; then
    return 0
  fi
  tier=${STATE_FILE_ABS#"$prefix"}
  tier=${tier%"$suffix"}
  write_state="$REPO_ROOT/.contributor-docs/write-state.json"
  if [[ ! $tier =~ ^[1-6]$ ]] || ! jq -e --arg f "$FILENAME" --argjson tier "$tier" '
    .step == ("write_tier_" + ($tier | tostring)) and .currentTier == $tier and
    (.blockedCollisions | type == "array" and length == 0) and .gapTransition == null and
    (.writeQueue | index($f)) != null and .provenance[$f].tier == $tier
  ' "$write_state" >/dev/null; then
    echo "PROCESSOR_AUTHORITY_INVALID: current tier or collision set changed" >&2
    return 1
  fi
  if ! jq -e --arg f "$FILENAME" '
    .provenance[$f].writeStatus == "written" and
    (.provenance[$f].writtenHash | type == "string" and test("^[0-9a-f]{64}$"))
  ' "$write_state" >/dev/null; then
    echo "WRITE_INCOMPLETE: '${FILENAME}' has no canonical written record" >&2
    return 1
  fi
  if ! jq -e --arg f "$FILENAME" --arg hash "$PLAN_HASH" '
    def sha256: type == "string" and test("^[0-9a-f]{64}$");
    def exact_keys($value; $want):
      ($value | type == "object") and (($value | keys | sort) == ($want | sort));
    def gap_item($gap):
      exact_keys($gap; ["path","type","tier","reason"])
      and ($gap.path | type == "string" and length > 0)
      and ($gap.reason | type == "string" and (gsub("[[:space:]]"; "") | length) > 0)
      and (($gap.type == "concept" and $gap.tier == 2) or
        ($gap.type == "algorithm" and $gap.tier == 3));
    .provenance[$f] as $entry |
    exact_keys($entry.writerReport;
      ["reportedBy","authorizedPlanHash","authorizedFromHash","writtenHash","gaps"]) and
    $entry.writerReport.reportedBy == $f and
    $entry.writerReport.authorizedPlanHash == $hash and
    ($entry.writerReport.authorizedFromHash | sha256) and
    $entry.writerReport.writtenHash == $entry.writtenHash and
    ($entry.writerReport.writtenHash | sha256) and
    ($entry.writerReport.gaps | type == "array") and
    all($entry.writerReport.gaps[]; gap_item(.)) and
    (($entry.writerReport.gaps | map([.path,.type,.tier]) | length) ==
      ($entry.writerReport.gaps | map([.path,.type,.tier]) | unique | length)) and
    ($entry.writerReport.gaps | group_by(.path) |
      all(.[]; (map({type:.type,tier:.tier}) | unique | length) == 1))
  ' "$write_state" >/dev/null; then
    echo "GAP_REPORT_SET_INVALID: '${FILENAME}' has no bound writer report" >&2
    return 1
  fi
  target_file=$(realpath -m -- "$REPO_ROOT/$FILENAME")
  expected_hash=$(jq -r --arg f "$FILENAME" '.provenance[$f].writtenHash' "$write_state")
  if [[ $target_file != "$REPO_ROOT/"* ]] || [[ ! -f $target_file ]]; then
    echo "WRITTEN_BYTES_CHANGED: '${FILENAME}' is absent or outside the repository" >&2
    return 1
  fi
  actual_hash=$(sha256sum -- "$target_file" | cut -d ' ' -f1)
  if [[ $actual_hash != "$expected_hash" ]]; then
    echo "WRITTEN_BYTES_CHANGED: '${FILENAME}' expected=${expected_hash} actual=${actual_hash}" >&2
    return 1
  fi
}

bash "$SCRIPT_DIR/init-state.sh" --assert-plan-authority "$PLAN_HASH"

if ! jq -e --arg hash "$PLAN_HASH" '.authorizedPlanHash == $hash' "$STATE_FILE" >/dev/null; then
  echo "PLAN_DRIFT_BLOCKED: processor authority does not match ${PLAN_HASH}" >&2
  exit 1
fi

# Write-tier completion additionally revalidates the exact operation snapshot and
# canonical record-write commit. Audit fact-check processors share this helper but
# have their own stamped durable evidence.
assert_processor_completion_authority

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
bash "$SCRIPT_DIR/init-state.sh" --assert-plan-authority "$PLAN_HASH"
if ! jq -e --arg hash "$PLAN_HASH" '.authorizedPlanHash == $hash' "$STATE_FILE" >/dev/null; then
  echo "PLAN_DRIFT_BLOCKED: processor authority does not match ${PLAN_HASH}" >&2
  exit 1
fi
assert_processor_completion_authority
mv "$TEMP" "$STATE_FILE"
trap - EXIT
