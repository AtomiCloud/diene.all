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

bash "$SCRIPT_DIR/init-state.sh" --assert-plan-authority "$PLAN_HASH"

if ! jq -e --arg hash "$PLAN_HASH" '.authorizedPlanHash == $hash' "$STATE_FILE" >/dev/null; then
  echo "PLAN_DRIFT_BLOCKED: processor authority does not match ${PLAN_HASH}" >&2
  exit 1
fi

# Write-tier completion additionally requires the canonical record-write commit. Audit
# fact-check processors share this helper but have their own stamped durable evidence.
if [[ $STATE_FILE_ABS == "$REPO_ROOT"/.contributor-docs/write-tier-*/state.json ]]; then
  WRITE_STATE="$REPO_ROOT/.contributor-docs/write-state.json"
  if ! jq -e --arg f "$FILENAME" '
    .provenance[$f].writeStatus == "written" and
    (.provenance[$f].writtenHash | type == "string" and test("^[0-9a-f]{64}$"))
  ' "$WRITE_STATE" >/dev/null; then
    echo "WRITE_INCOMPLETE: '${FILENAME}' has no canonical written record" >&2
    exit 1
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
  ' "$WRITE_STATE" >/dev/null; then
    echo "GAP_REPORT_SET_INVALID: '${FILENAME}' has no bound writer report" >&2
    exit 1
  fi
fi

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
mv "$TEMP" "$STATE_FILE"
trap - EXIT
