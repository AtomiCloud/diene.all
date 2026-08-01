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

  contract_failure() {
    printf '❌ %s\n' "$1" >&2
    FAILURES=$((FAILURES + 1))
  }

  # A canonical marker is an exact, single HTML-comment line followed by one JSON
  # fence. Matching a marker substring or accepting a second marker would silently
  # select the wrong contract copy.
  extract_marked_json() {
    local file=$1 marker=$2 output=$3 exact count
    exact="<!-- canonical-block: ${marker} -->"
    count=$(awk -v exact="$exact" '
      { line = $0; sub(/^[[:space:]]*/, "", line); sub(/[[:space:]]*$/, "", line) }
      line == exact { count++ }
      END { print count + 0 }
    ' "$file")
    if [[ $count != 1 ]]; then
      printf 'MARKER_INVALID %s count=%s file=%s\n' "$marker" "${count:-0}" "$file" >&2
      return 1
    fi
    awk -v exact="$exact" '
      {
        line = $0
        sub(/^[[:space:]]*/, "", line)
        sub(/[[:space:]]*$/, "", line)
      }
      line == exact { seen = 1; next }
      seen && !opened {
        if ($0 ~ /^[[:space:]]*$/) next
        if ($0 ~ /^[[:space:]]*```json[[:space:]]*$/) { opened = 1; next }
        bad = 1; exit
      }
      opened && !closed {
        if ($0 ~ /^[[:space:]]*```[[:space:]]*$/) { closed = 1; exit }
        sub(/^[[:space:]]{0,3}/, "")
        print
      }
      END { if (!seen || !opened || !closed || bad) exit 1 }
    ' "$file" >"$output"
  }

  canonical_shape() {
    local file=$1 marker=$2 output=$3 json
    json="$CONTROL_DIR/${marker}.$$.json"
    if ! extract_marked_json "$file" "$marker" "$json"; then
      return 1
    fi
    jq -ceS '[paths as $p | (getpath($p) | type) as $t |
      select($t != "array" and $t != "object") | {path:$p,type:$t}]' \
      "$json" >"$output"
  }

  normalise_step_array() {
    local json=$1 output=$2
    if ! jq -e '
      type == "array" and length > 0
      and all(.[]; type == "string" and test("^[a-z][a-z0-9_]*$"))
      and (length == (unique | length))
    ' "$json" >/dev/null; then
      return 1
    fi
    jq -r '.[]' "$json" | LC_ALL=C sort >"$output"
  }

  phase_step_set() {
    local output=$1 schema="$CONTROL_DIR/phase-write-state-schema.json"
    local array="$CONTROL_DIR/phase-write-legal-steps.json"
    if ! extract_marked_json "$WRITE_PHASE" write-state-schema "$schema" ||
      ! jq -ce '
        if type == "object" and (.step | type == "string") then
          .step | split("|") | map(gsub("^[[:space:]]+|[[:space:]]+$"; ""))
        else error("write-state-schema.step must be a string") end
      ' "$schema" >"$array"; then
      return 1
    fi
    normalise_step_array "$array" "$output"
  }

  state_machine_step_set() {
    local output=$1
    awk '
      /^## State Machine$/ { inside = 1; next }
      inside && /^## / { exit }
      inside {
        while (match($0, /\[[a-z][a-z0-9_]*\]/)) {
          print substr($0, RSTART + 1, RLENGTH - 2)
          $0 = substr($0, RSTART + RLENGTH)
        }
      }
    ' "$WRITE_PHASE" | LC_ALL=C sort -u >"$output"
    [[ -s $output ]]
  }

  dispatch_step_set() {
    local output=$1 raw="$CONTROL_DIR/dispatch-raw.$$.txt"
    awk '
      /^## Step Dispatch$/ { inside = 1; next }
      inside && /^### Gap Sub-Dispatch$/ { exit }
      inside && /^\| `/ {
        row = $0
        sub(/^\| `/, "", row)
        sub(/`.*/, "", row)
        print row
      }
    ' "$WRITE_PHASE" >"$raw"
    [[ -s $raw ]] || return 1
    if [[ -n $(LC_ALL=C sort "$raw" | uniq -d) ]] ||
      ! awk '/^[a-z][a-z0-9_]*$/ { next } { exit 1 }' "$raw"; then
      return 1
    fi
    LC_ALL=C sort "$raw" >"$output"
  }

  # This accepts a path explicitly so the destructive fixture below executes the
  # exact predicate against a copied state-agent, not an imitation of the hook.
  check_write_legal_steps() {
    local agent=$1 scratch=$2 phase_steps agent_json agent_steps machine_steps dispatch_steps
    phase_steps="$scratch/phase-steps"
    agent_json="$scratch/agent-steps.json"
    agent_steps="$scratch/agent-steps"
    machine_steps="$scratch/machine-steps"
    dispatch_steps="$scratch/dispatch-steps"
    mkdir -p "$scratch"
    if ! phase_step_set "$phase_steps"; then
      printf 'WRITE_LEGAL_STEP_SOURCE_INVALID phase\n' >&2
      return 1
    fi
    if ! extract_marked_json "$agent" write-legal-steps "$agent_json" ||
      ! normalise_step_array "$agent_json" "$agent_steps"; then
      printf 'WRITE_LEGAL_STEP_SOURCE_INVALID state-agent\n' >&2
      return 1
    fi
    if ! state_machine_step_set "$machine_steps" || ! dispatch_step_set "$dispatch_steps"; then
      printf 'WRITE_LEGAL_STEP_SOURCE_INVALID phase-structure\n' >&2
      return 1
    fi
    if ! cmp -s "$phase_steps" "$agent_steps" ||
      ! cmp -s "$phase_steps" "$machine_steps" ||
      ! cmp -s "$phase_steps" "$dispatch_steps"; then
      printf 'WRITE_LEGAL_STEP_DRIFT\n' >&2
      diff -u "$phase_steps" "$agent_steps" || true
      diff -u "$phase_steps" "$machine_steps" || true
      diff -u "$phase_steps" "$dispatch_steps" || true
      return 1
    fi
  }

  assert_object_shape() {
    local label=$1 file=$2 marker=$3 expected_count=$4 required_key=$5 json
    json="$CONTROL_DIR/${label// /-}.json"
    if ! extract_marked_json "$file" "$marker" "$json" ||
      ! jq -e --arg key "$required_key" --argjson count "$expected_count" '
        type == "object" and (keys | length) == $count and has($key)
      ' "$json" >/dev/null; then
      contract_failure "Malformed ${label} canonical block"
    fi
  }

  assert_exact_keys() {
    local label=$1 file=$2 marker=$3 expected=$4 json
    json="$CONTROL_DIR/${label// /-}.keys.json"
    if ! extract_marked_json "$file" "$marker" "$json" ||
      ! jq -e --argjson expected "$expected" '
        type == "object" and ((keys | sort) == ($expected | sort))
      ' "$json" >/dev/null; then
      contract_failure "Unexpected ${label} key set"
    fi
  }

  MARKERS=(
    write-state-schema
    write-provenance-record
    write-approval-record
    write-collision-record
    write-audit-repair-record
    gap-transition-record
    gap-plan-mutation-record
  )
  for MARKER in "${MARKERS[@]}"; do
    if ! canonical_shape "$WRITE_PHASE" "$MARKER" "$CONTROL_DIR/phase-$MARKER.canonical" ||
      ! canonical_shape "$WRITE_AGENT" "$MARKER" "$CONTROL_DIR/agent-$MARKER.canonical"; then
      contract_failure "Malformed or duplicate canonical block: $MARKER"
    elif ! cmp -s "$CONTROL_DIR/phase-$MARKER.canonical" "$CONTROL_DIR/agent-$MARKER.canonical"; then
      contract_failure "Canonical block drift: $MARKER"
    fi
  done

  assert_object_shape 'write state schema' "$WRITE_PHASE" write-state-schema 14 authorizedPlanHash
  assert_object_shape 'write state schema mirror' "$WRITE_AGENT" write-state-schema 14 authorizedPlanHash
  assert_object_shape 'gap transition' "$WRITE_PHASE" gap-transition-record 10 planMutation
  assert_object_shape 'gap transition mirror' "$WRITE_AGENT" gap-transition-record 10 planMutation
  assert_object_shape 'gap plan mutation' "$WRITE_PHASE" gap-plan-mutation-record 5 candidatePath
  assert_object_shape 'gap plan mutation mirror' "$WRITE_AGENT" gap-plan-mutation-record 5 candidatePath
  WRITE_SCHEMA_KEYS='["step","scaffoldComplete","currentTier","tiersCompleted","filesWritten","filesTotal","writeQueue","provenance","approvedOverwrites","blockedCollisions","auditRepair","gapTransition","gapsResolved","authorizedPlanHash"]'
  GAP_KEYS='["status","reports","gapPaths","expectedScaffold","replayTier","requeued","resetTiers","cleanedTiers","openedAt","planMutation"]'
  GAP_MUTATION_KEYS='["candidatePath","fromPlanHash","toPlanHash","addedPlanEntries","addedCrossLinks"]'
  assert_exact_keys 'write state schema' "$WRITE_PHASE" write-state-schema "$WRITE_SCHEMA_KEYS"
  assert_exact_keys 'write state schema mirror' "$WRITE_AGENT" write-state-schema "$WRITE_SCHEMA_KEYS"
  assert_exact_keys 'gap transition' "$WRITE_PHASE" gap-transition-record "$GAP_KEYS"
  assert_exact_keys 'gap transition mirror' "$WRITE_AGENT" gap-transition-record "$GAP_KEYS"
  assert_exact_keys 'gap plan mutation' "$WRITE_PHASE" gap-plan-mutation-record "$GAP_MUTATION_KEYS"
  assert_exact_keys 'gap plan mutation mirror' "$WRITE_AGENT" gap-plan-mutation-record "$GAP_MUTATION_KEYS"

  if ! check_write_legal_steps "$WRITE_AGENT" "$CONTROL_DIR/real-legal-steps"; then
    contract_failure 'WRITE_LEGAL_STEP_DRIFT or malformed legal-step source'
  fi

  FIXTURE_AGENT="$CONTROL_DIR/state-agent-without-write-tier-5.md"
  if ! awk '
    {
      line = $0
      sub(/^[[:space:]]*/, "", line)
      sub(/[[:space:]]*$/, "", line)
    }
    line == "<!-- canonical-block: write-legal-steps -->" { in_steps = 1 }
    in_steps && /"write_tier_5",/ {
      removed++
      if (removed > 1) { bad = 1; exit }
      next
    }
    { print }
    END { if (removed != 1 || bad) exit 1 }
  ' "$WRITE_AGENT" >"$FIXTURE_AGENT"; then
    contract_failure 'Legal-step destructive fixture could not remove exactly one marked element'
  else
    if FIXTURE_OUTPUT=$(check_write_legal_steps "$FIXTURE_AGENT" "$CONTROL_DIR/fixture-legal-steps" 2>&1); then
      contract_failure 'Legal-step destructive fixture stayed green'
    elif [[ $FIXTURE_OUTPUT != *WRITE_LEGAL_STEP_DRIFT* ]]; then
      contract_failure 'Legal-step destructive fixture failed for the wrong reason'
    elif ! check_write_legal_steps "$WRITE_AGENT" "$CONTROL_DIR/real-legal-steps-restored"; then
      contract_failure 'Real legal-step inputs did not recover green after fixture'
    else
      echo '✅ Legal-step destructive fixture rejected a missing state-agent step and real inputs recovered'
    fi
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
def current_plan($state):
  if $state.authorizedPlanHash != $state.livePlanHash then
    refuse("PLAN_DRIFT_BLOCKED")
  else $state end;
def exact_mutation($data):
  ($data.candidateHash | type == "string")
  and ($data.fromPlanHash | type == "string")
  and ($data.toPlanHash | type == "string")
  and $data.candidateHash == $data.toPlanHash
  and $data.fromPlanHash != $data.toPlanHash
  and ($data.addedPlanEntries | type == "array")
  and ($data.addedCrossLinks | type == "array")
  and $data.addedPlanEntries == $data.expectedAddedPlanEntries
  and $data.addedCrossLinks == $data.expectedAddedCrossLinks;
def gap_mutation($state): $state.gapPlanMutation;
def apply($state; $operation; $data):
  if $operation == "authorize-gap-plan" then
    if $state.gapStatus != null then refuse("GAP_TRANSITION_INVALID")
    elif $state.authorizedPlanHash != $state.livePlanHash then refuse("PLAN_DRIFT_BLOCKED")
    elif ($state.candidateHash // null) == null then refuse("GAP_PLAN_CANDIDATE_MISSING")
    elif (exact_mutation($data) | not) then refuse("GAP_PLAN_DELTA_INVALID")
    elif $data.fromPlanHash != $state.authorizedPlanHash or
      $state.candidateHash != $data.toPlanHash then refuse("GAP_PLAN_HASH_INVALID")
    else $state | .gapStatus = "enqueued" |
      .gapPlanMutation = {
        fromPlanHash:$data.fromPlanHash, toPlanHash:$data.toPlanHash,
        candidatePath:$data.candidatePath, addedPlanEntries:$data.addedPlanEntries,
        addedCrossLinks:$data.addedCrossLinks
      }
    end
  elif $operation == "apply-gap-plan" then
    if $state.gapStatus == "planned" and
      $state.authorizedPlanHash == $state.livePlanHash then $state
    elif $state.gapStatus != "enqueued" then refuse("GAP_TRANSITION_INVALID")
    elif (gap_mutation($state).fromPlanHash != $state.authorizedPlanHash) then
      refuse("GAP_PLAN_HASH_INVALID")
    elif $state.livePlanHash == gap_mutation($state).fromPlanHash and
      ($state.candidateHash // null) == null then refuse("GAP_PLAN_CANDIDATE_MISSING")
    elif $state.livePlanHash == gap_mutation($state).fromPlanHash and
      $state.candidateHash != gap_mutation($state).toPlanHash then refuse("GAP_PLAN_HASH_INVALID")
    elif $state.livePlanHash == gap_mutation($state).fromPlanHash and
      $state.candidateHash == gap_mutation($state).toPlanHash then
      $state | .livePlanHash = gap_mutation($state).toPlanHash |
        .authorizedPlanHash = gap_mutation($state).toPlanHash |
        .candidateHash = null | .gapStatus = "planned"
    elif $state.livePlanHash == gap_mutation($state).toPlanHash and
      ($state.candidateHash // null) == null then
      $state | .authorizedPlanHash = gap_mutation($state).toPlanHash |
        .gapStatus = "planned"
    else refuse("GAP_PLAN_HASH_INVALID") end
  elif $operation == "write-dispatch" or $operation == "audit-dispatch" or
    $operation == "advance-task-phase-to-audit" or
    $operation == "advance-task-phase-to-completed" then
    current_plan($state)
  elif $operation == "create-scaffold" then
    current_plan($state) |
    if $state.step != "scaffold_prepared" then refuse("SCAFFOLD_NOT_PREPARED")
    else $state end
  elif $operation == "prepare-scaffold" then
    current_plan($state) |
    if $state.step != "scaffold" then refuse("WRITE_TRANSITION_INVALID")
    else $state | .step = "scaffold_prepared" end
  elif $operation == "finalize-scaffold" then
    current_plan($state) |
    if $state.step != "scaffold_prepared" then refuse("WRITE_TRANSITION_INVALID")
    else $state | .step = "write_tier_1" end
  elif $operation == "complete-tier" then
    current_plan($state) |
    if ($state.pending | length) != 0 then refuse("WRITE_INCOMPLETE")
    else $state | .step = "completed" end
  elif $operation == "record-write" then
    current_plan($state) |
    if $data.returnedHash != $data.diskHash then refuse("WRITE_HASH_MISMATCH")
    else $state end
  elif $operation == "gap-advance" then
    current_plan($state) |
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

  # The reducer is intentionally a small executable model, but its names and record
  # shapes are tied back to the marked Markdown sources below.  It proves that every
  # ordinary dispatch/handoff shares the same approved-plan guard and that the only
  # successor is the named gap candidate transaction.
  PLAN_A=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
  PLAN_B=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
  PLAN_C=cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc
  PLAN_BASE=$(jq -cn --arg hash "$PLAN_A" '{step:"write_tier_1",pending:[],gapStatus:null,
    approvedPlanHash:$hash,authorizedPlanHash:$hash,livePlanHash:$hash,candidateHash:null,
    gapPlanMutation:null}')
  PLAN_MUTATION=$(jq -cn --arg from "$PLAN_A" --arg to "$PLAN_B" '{
    fromPlanHash:$from, toPlanHash:$to, candidateHash:$to, candidatePath:".contributor-docs/doc-plan.gap-candidate.yaml",
    addedPlanEntries:[{outputPath:"docs/a.mdx",container:"shared",entry:{path:"a.mdx",type:"concept",tier:1}}],
    addedCrossLinks:[{reportedBy:"docs/r.mdx",field:"concepts",target:"docs/a.mdx"}],
    expectedAddedPlanEntries:[{outputPath:"docs/a.mdx",container:"shared",entry:{path:"a.mdx",type:"concept",tier:1}}],
    expectedAddedCrossLinks:[{reportedBy:"docs/r.mdx",field:"concepts",target:"docs/a.mdx"}]
  }')

  CONTROL_FAILURES_BEFORE=$FAILURES
  for OPERATION in write-dispatch audit-dispatch advance-task-phase-to-audit advance-task-phase-to-completed; do
    if ! jq -n -L "$CONTROL_DIR" --argjson state "$PLAN_BASE" --arg operation "$OPERATION" \
      --argjson data '{}' -f "$CONTROL_DIR/reducer.jq" >/dev/null; then
      contract_failure "Healthy ${OPERATION} was plan-blocked"
    fi
    TAMPERED=$(jq -c --arg hash "$PLAN_C" '.livePlanHash = $hash' <<<"$PLAN_BASE")
    printf '%s' "$TAMPERED" >"$CONTROL_DIR/${OPERATION}.before"
    if OUTPUT=$(jq -n -L "$CONTROL_DIR" --argjson state "$TAMPERED" --arg operation "$OPERATION" \
      --argjson data '{}' -f "$CONTROL_DIR/reducer.jq" 2>&1); then
      contract_failure "Post-approval tamper passed ${OPERATION}"
    elif [[ $OUTPUT != *PLAN_DRIFT_BLOCKED* ]]; then
      contract_failure "Post-approval tamper failed ${OPERATION} for the wrong reason"
    fi
    printf '%s' "$TAMPERED" >"$CONTROL_DIR/${OPERATION}.after"
    if ! cmp -s "$CONTROL_DIR/${OPERATION}.before" "$CONTROL_DIR/${OPERATION}.after"; then
      contract_failure "Post-approval tamper mutated reducer state for ${OPERATION}"
    fi
  done
  if [[ $FAILURES -eq $CONTROL_FAILURES_BEFORE ]]; then
    echo '✅ Ordinary write/audit dispatch and both terminal handoffs rejected post-approval plan tampering'
  fi

  CONTROL_FAILURES_BEFORE=$FAILURES
  if ! AUTHORIZED=$(jq -n -L "$CONTROL_DIR" --argjson state \
    "$(jq -c --arg hash "$PLAN_B" '.candidateHash = $hash' <<<"$PLAN_BASE")" \
    --arg operation authorize-gap-plan --argjson data "$PLAN_MUTATION" -f "$CONTROL_DIR/reducer.jq"); then
    contract_failure 'Valid authorize-gap-plan was refused'
  elif [[ $(jq -r '.gapStatus' <<<"$AUTHORIZED") != enqueued ]] ||
    [[ $(jq -r '.authorizedPlanHash' <<<"$AUTHORIZED") != "$PLAN_A" ]]; then
    contract_failure 'authorize-gap-plan changed live authority before apply'
  fi

  if [[ -n ${AUTHORIZED:-} ]]; then
    if ! APPLIED=$(jq -n -L "$CONTROL_DIR" --argjson state "$AUTHORIZED" \
      --arg operation apply-gap-plan --argjson data '{}' -f "$CONTROL_DIR/reducer.jq"); then
      contract_failure 'Valid apply-gap-plan was refused'
    elif [[ $(jq -r '.gapStatus' <<<"$APPLIED") != planned ]] ||
      [[ $(jq -r '.authorizedPlanHash' <<<"$APPLIED") != "$PLAN_B" ]] ||
      ! jq -n -L "$CONTROL_DIR" --argjson state "$APPLIED" --arg operation write-dispatch \
        --argjson data '{}' -f "$CONTROL_DIR/reducer.jq" >/dev/null; then
      contract_failure 'Gap successor did not authorize ordinary dispatch'
    fi
    if [[ $FAILURES -eq $CONTROL_FAILURES_BEFORE ]]; then
      echo '✅ Exact discovered-gap successor was authorized, applied, and accepted by ordinary dispatch'
    fi

    CONTROL_FAILURES_BEFORE=$FAILURES
    BAD_DELTA=$(jq -c '.addedPlanEntries += [{outputPath:"docs/extra.mdx",container:"shared",entry:{path:"extra.mdx",type:"concept",tier:1}}]' <<<"$PLAN_MUTATION")
    if OUTPUT=$(jq -n -L "$CONTROL_DIR" --argjson state \
      "$(jq -c --arg hash "$PLAN_B" '.candidateHash = $hash' <<<"$PLAN_BASE")" \
      --arg operation authorize-gap-plan --argjson data "$BAD_DELTA" -f "$CONTROL_DIR/reducer.jq" 2>&1); then
      contract_failure 'Extra semantic gap delta was accepted'
    elif [[ $OUTPUT != *GAP_PLAN_DELTA_INVALID* ]]; then
      contract_failure 'Extra semantic gap delta failed for the wrong reason'
    fi
    if [[ $FAILURES -eq $CONTROL_FAILURES_BEFORE ]]; then
      echo '✅ Extra semantic gap delta was rejected without changing authority'
    fi

    CONTROL_FAILURES_BEFORE=$FAILURES
    WRONG_CANDIDATE=$(jq -c --arg hash "$PLAN_C" '.candidateHash = $hash' <<<"$AUTHORIZED")
    if OUTPUT=$(jq -n -L "$CONTROL_DIR" --argjson state "$WRONG_CANDIDATE" \
      --arg operation apply-gap-plan --argjson data '{}' -f "$CONTROL_DIR/reducer.jq" 2>&1); then
      contract_failure 'Wrong gap candidate hash was accepted'
    elif [[ $OUTPUT != *GAP_PLAN_HASH_INVALID* ]]; then
      contract_failure 'Wrong gap candidate hash failed for the wrong reason'
    fi
    if [[ $FAILURES -eq $CONTROL_FAILURES_BEFORE ]]; then
      echo '✅ Wrong gap candidate hash was rejected without changing authority'
    fi

    CONTROL_FAILURES_BEFORE=$FAILURES
    MISSING_CANDIDATE=$(jq -c '.candidateHash = null' <<<"$AUTHORIZED")
    if OUTPUT=$(jq -n -L "$CONTROL_DIR" --argjson state "$MISSING_CANDIDATE" \
      --arg operation apply-gap-plan --argjson data '{}' -f "$CONTROL_DIR/reducer.jq" 2>&1); then
      contract_failure 'Missing gap candidate was accepted'
    elif [[ $OUTPUT != *GAP_PLAN_CANDIDATE_MISSING* ]]; then
      contract_failure 'Missing gap candidate failed for the wrong reason'
    fi
    if [[ $FAILURES -eq $CONTROL_FAILURES_BEFORE ]]; then
      echo '✅ Missing gap candidate was rejected without changing authority'
    fi

    CONTROL_FAILURES_BEFORE=$FAILURES
    CRASH_TUPLE=$(jq -c --arg hash "$PLAN_B" '.livePlanHash = $hash | .candidateHash = null' <<<"$AUTHORIZED")
    if ! CRASH_ADOPTED=$(jq -n -L "$CONTROL_DIR" --argjson state "$CRASH_TUPLE" \
      --arg operation apply-gap-plan --argjson data '{}' -f "$CONTROL_DIR/reducer.jq") ||
      ! CRASH_IDEMPOTENT=$(jq -n -L "$CONTROL_DIR" --argjson state "$CRASH_ADOPTED" \
        --arg operation apply-gap-plan --argjson data '{}' -f "$CONTROL_DIR/reducer.jq") ||
      ! cmp -s <(jq -cS . <<<"$CRASH_ADOPTED") <(jq -cS . <<<"$CRASH_IDEMPOTENT"); then
      contract_failure 'Rename-before-state crash tuple was not adopted idempotently'
    fi
    if [[ $FAILURES -eq $CONTROL_FAILURES_BEFORE ]]; then
      echo '✅ Rename-before-state crash tuple was adopted and replayed idempotently'
    fi
  fi

  for LITERAL in authorizedPlanHash authorize-gap-plan apply-gap-plan PLAN_DRIFT_BLOCKED \
    GAP_PLAN_DELTA_INVALID GAP_PLAN_HASH_INVALID GAP_PLAN_CANDIDATE_MISSING; do
    if ! rg -qF "$LITERAL" "$WRITE_PHASE" || ! rg -qF "$LITERAL" "$WRITE_AGENT"; then
      contract_failure "Reducer literal is not documented: $LITERAL"
    fi
  done
  echo '✅ Plan-authority reducer controls passed (tamper, successor, refusals, crash adoption)'

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
