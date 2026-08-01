#!/usr/bin/env bash
# Usage: mark-done.sh <state-file> <filename> --plan-hash <sha256>
# Moves filename from pendingFiles to processedFiles.
#
# Refuses a filename that was never queued. A typo or a stale completion must not
# silently append an unknown path to processedFiles -- that corrupts resumable
# state in a way the next run cannot detect.
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=docs/standards/contributor-docs/scripts/init-state.sh
source "$SCRIPT_DIR/init-state.sh"

assert_processor_membership() {
  local state_file=$1 filename=$2 plan_hash=$3 state_abs

  state_abs=$(realpath -m -- "$state_file")
  if [[ ! -f $state_file ]] || ! jq -e --arg file "$filename" --arg hash "$plan_hash" '
      . as $processor |
      ($processor.authorizedPlanHash == $hash) and
      ($processor | has("recordWriteAuthorizations")) and
      ($processor.filesToProcess | type == "array") and
      (($processor.filesToProcess | length) ==
        ($processor.filesToProcess | unique | length)) and
      ($processor.pendingFiles | type == "array") and
      (($processor.pendingFiles | length) ==
        ($processor.pendingFiles | unique | length)) and
      ($processor.processedFiles | type == "array") and
      (($processor.processedFiles | length) ==
        ($processor.processedFiles | unique | length)) and
      (($processor.filesToProcess | index($file)) != null) and
      (all($processor.pendingFiles[]; . as $path |
        ($processor.filesToProcess | index($path)) != null)) and
      (all($processor.processedFiles[]; . as $path |
        ($processor.filesToProcess | index($path)) != null)) and
      (all($processor.pendingFiles[]; . as $path |
        ($processor.processedFiles | index($path)) == null)) and
      ((($processor.pendingFiles + $processor.processedFiles) | sort) ==
        ($processor.filesToProcess | sort))
    ' "$state_file" >/dev/null; then
    echo "PROCESSOR_AUTHORITY_INVALID: processor membership or plan authority changed" >&2
    return 1
  fi
  if [[ $state_abs == "$REPO_ROOT/.contributor-docs/fact-check/state.json" ]] &&
    ! jq -e '.recordWriteAuthorizations == null' "$state_file" >/dev/null; then
    echo "PROCESSOR_AUTHORITY_INVALID: fact-check processor has stale authorization format" >&2
    return 1
  fi
}

assert_completion_authority() {
  local state_file=$1 filename=$2 plan_hash=$3 state_abs

  assert_plan_authority "$plan_hash"
  assert_processor_membership "$state_file" "$filename" "$plan_hash"
  state_abs=$(realpath -m -- "$state_file")
  if [[ $state_abs == "$REPO_ROOT/.contributor-docs/write-tier-"*"/state.json" ]]; then
    assert_record_write_authority committed "$state_file" "$filename" "$plan_hash" >/dev/null
  fi
}

mark_done_main() {
  [[ $# -eq 4 && $3 == "--plan-hash" && $4 =~ ^[0-9a-f]{64}$ ]] || {
    echo "❌ Usage: mark-done.sh <state-file> <filename> --plan-hash <64-hex>" >&2
    exit 1
  }

  local state_file=$1 filename=$2 plan_hash=$4
  local authority_preimage processor_preimage

  acquire_authority_lock
  trap 'authority_transaction_cleanup "$?"' EXIT

  assert_completion_authority "$state_file" "$filename" "$plan_hash"

  # Already processed is an idempotent success only after the same fresh authority,
  # report, disk, and processor-format validation required for a new commit.
  if jq -e --arg file "$filename" \
    '.processedFiles | index($file) != null' "$state_file" >/dev/null; then
    echo "✅ '${filename}' already marked done"
    release_authority_lock
    trap - EXIT
    return 0
  fi

  authority_preimage=$(processor_authority_snapshot "$state_file" "$filename")
  processor_preimage=$(authority_snapshot "$state_file")

  CONTRIBUTOR_DOCS_TEMP_FILE=$(mktemp "${state_file}.XXXXXX")
  jq --arg file "$filename" '
    .pendingFiles -= [$file] |
    .processedFiles += [$file] |
    .processedFiles |= unique
  ' "$state_file" >"$CONTRIBUTOR_DOCS_TEMP_FILE"

  assert_completion_authority "$state_file" "$filename" "$plan_hash"
  if ! jq -e -s --arg file "$filename" '
      .[1] == (.[0] |
        .pendingFiles -= [$file] |
        .processedFiles += [$file] |
        .processedFiles |= unique)
    ' "$state_file" "$CONTRIBUTOR_DOCS_TEMP_FILE" >/dev/null; then
    echo "PROCESSOR_AUTHORITY_INVALID: staged completion is not the exact processor transition" >&2
    exit 1
  fi

  authority_contract_test_barrier mark-before-cas
  if [[ $(processor_authority_snapshot "$state_file" "$filename") != "$authority_preimage" ]] ||
    [[ $(authority_snapshot "$state_file") != "$processor_preimage" ]]; then
    echo "PROCESSOR_AUTHORITY_INVALID: authority or processor preimage changed before completion commit" >&2
    exit 1
  fi

  mv "$CONTRIBUTOR_DOCS_TEMP_FILE" "$state_file"
  CONTRIBUTOR_DOCS_TEMP_FILE=
  release_authority_lock
  trap - EXIT
}

mark_done_main "$@"
