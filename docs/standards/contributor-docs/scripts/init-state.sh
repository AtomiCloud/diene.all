#!/usr/bin/env bash
# Usage: <file-list> | init-state.sh <state-file> <source-paths-json> <concurrent> <output-dir> --plan-hash <sha256>
#        init-state.sh --check-write-contract
#        init-state.sh --assert-plan-authority <sha256> [authority paths...]
# Reads file list from stdin, one file per line.
#
# Feed the list with printf, never echo: `echo "a.mdx\nb.mdx"` emits a literal
# backslash-n in Bash and records one filename instead of two.
#   printf '%s\n' a.mdx b.mdx | init-state.sh ...
set -euo pipefail

REPO_ROOT=$(git rev-parse --show-toplevel)

# Validate the immutable approved-plan root, every complete closed successor, the
# current authorized hash, the exact live-plan bytes, and the absent candidate. The
# processor helpers call this again immediately before their atomic rename so an
# earlier state-agent assessment cannot be used as a stale capability.
assert_plan_authority() {
  local expected_hash=$1
  local plan_state=${2:-"$REPO_ROOT/.contributor-docs/plan-state.json"}
  local write_state=${3:-"$REPO_ROOT/.contributor-docs/write-state.json"}
  local live_plan=${4:-"$REPO_ROOT/.contributor-docs/doc-plan.yaml"}
  local candidate_plan=${5:-"$REPO_ROOT/.contributor-docs/doc-plan.gap-candidate.yaml"}
  local actual_hash result

  if [[ ! $expected_hash =~ ^[0-9a-f]{64}$ ]] ||
    [[ ! -f $plan_state ]] || [[ ! -f $write_state ]] || [[ ! -f $live_plan ]]; then
    echo "PLAN_DRIFT_BLOCKED: expected=${expected_hash} actual=absent" >&2
    return 1
  fi
  if [[ -e $candidate_plan ]]; then
    echo "PLAN_DRIFT_BLOCKED: expected=${expected_hash} actual=candidate-present" >&2
    return 1
  fi

  actual_hash=$(sha256sum -- "$live_plan" | cut -d ' ' -f1)
  if ! result=$(jq -r -s --arg expected "$expected_hash" --arg actual "$actual_hash" '
    def sha256: type == "string" and test("^[0-9a-f]{64}$");
    def timestamp:
      type == "string" and
      test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$");
    def exact_keys($value; $want):
      ($value | type == "object") and (($value | keys | sort) == ($want | sort));
    def normalized_path($value):
      type == "string" and length > 0 and (startswith("/") | not) and
      (split("/") | all(. != "" and . != "." and . != ".."));
    def expected_added_entries($gap_paths):
      $gap_paths | map({outputPath:.path,type:.type,tier:.tier}) |
      sort_by([.outputPath,.type,.tier]);
    def expected_added_links($reports):
      [$reports[] as $report | $report.gaps[] |
        {reportedBy:$report.reportedBy,
         field:(if .type == "concept" then "concepts" else "algorithms" end),
         target:.path}] |
      sort_by([.reportedBy,.field,.target]) | unique_by([.reportedBy,.field,.target]);
    def valid_plan($plan):
      exact_keys($plan; ["docsRoot","modules","shared","topLevel","adrs","indexes"])
      and ($plan.docsRoot | normalized_path(.))
      and ($plan.modules | type == "array")
      and all($plan.modules[];
        exact_keys(.; ["name","description","files"])
        and (.name | type == "string" and length > 0)
        and (.description | type == "string") and (.files | type == "array"))
      and exact_keys($plan.shared; ["files"]) and ($plan.shared.files | type == "array")
      and ($plan.topLevel | type == "array") and ($plan.adrs | type == "array")
      and ($plan.indexes | type == "array");
    def plan_entries($plan):
      ([ $plan.modules[] as $module | $module.files[] as $entry |
          {outputPath:($plan.docsRoot + "/" + $entry.path),
           container:("module:" + $module.name),entry:$entry} ]
       + [ $plan.shared.files[] as $entry |
          {outputPath:($plan.docsRoot + "/" + $entry.path),container:"shared",entry:$entry} ]
       + [ $plan.topLevel[] as $entry |
          {outputPath:($plan.docsRoot + "/" + $entry.path),container:"topLevel",entry:$entry} ]
       + [ $plan.adrs[] as $entry |
          {outputPath:($plan.docsRoot + "/" + $entry.path),container:"adrs",entry:$entry} ]
       + [ $plan.indexes[] as $entry |
          {outputPath:($plan.docsRoot + "/" + $entry.path),container:"indexes",entry:$entry} ]) |
      sort_by(.outputPath);
    def plan_links($plan):
      [plan_entries($plan)[] as $wrapped |
        (($wrapped.entry.crossLinks // {}) | to_entries[]) as $links |
        $links.value[] as $target |
        {reportedBy:$wrapped.outputPath,field:$links.key,
         target:($plan.docsRoot + "/" + $target)}] |
      sort_by([.reportedBy,.field,.target]) | unique_by([.reportedBy,.field,.target]);
    def stored_entries_current($mutation; $live):
      (plan_entries($live)) as $current |
      all($mutation.addedPlanEntries[]; . as $added |
        ($current | map(select(.outputPath == $added.outputPath)) | .[0]) as $now |
        $now != null and $now.container == $added.container and
        (($now.entry | del(.crossLinks)) == ($added.entry | del(.crossLinks))) and
        (($added.entry.crossLinks // {}) | to_entries |
          all(.[]; . as $links |
            all($links.value[]; . as $target |
              (($now.entry.crossLinks[$links.key] // []) | index($target)) != null))));
    def mutation($value; $reports; $gap_paths; $live):
      exact_keys($value;
        ["candidatePath","fromPlanHash","toPlanHash","addedPlanEntries","addedCrossLinks"])
      and $value.candidatePath == ".contributor-docs/doc-plan.gap-candidate.yaml"
      and ($value.fromPlanHash | sha256) and ($value.toPlanHash | sha256)
      and $value.fromPlanHash != $value.toPlanHash
      and ($value.addedPlanEntries | type == "array" and length > 0)
      and $value.addedPlanEntries == ($value.addedPlanEntries | sort_by(.outputPath))
      and (($value.addedPlanEntries | map(.outputPath) | length) ==
        ($value.addedPlanEntries | map(.outputPath) | unique | length))
      and all($value.addedPlanEntries[]; . as $added |
        exact_keys($added; ["outputPath","container","entry"])
        and ($added.outputPath | normalized_path(.))
        and ($added.container | type == "string" and
          test("^(shared|topLevel|adrs|indexes|module:[^/]+)$"))
        and ($added.entry | type == "object")
        and ((["path","type","tier","description","sources"] -
          ($added.entry | keys)) | length == 0)
        and (((($added.entry | keys) -
          ["path","type","conceptType","tier","description","sources","crossLinks","tags"]) |
          length) == 0)
        and ($added.entry.path | normalized_path(.))
        and ($added.outputPath | endswith("/" + $added.entry.path))
        and (($added.entry.type == "concept" and $added.entry.tier == 2) or
          ($added.entry.type == "algorithm" and $added.entry.tier == 3))
        and ($added.entry.description | type == "string" and
          (gsub("[[:space:]]"; "") | length) > 0)
        and ($added.entry.sources | type == "array" and length > 0)
        and all($added.entry.sources[]; type == "string" and length > 0)
        and (($added.entry.conceptType // "") | type == "string")
        and (($added.entry.crossLinks // {}) | type == "object")
        and all(($added.entry.crossLinks // {})[]; type == "array" and
          all(.[]; type == "string" and length > 0))
        and (($added.entry.tags // []) | type == "array")
        and all(($added.entry.tags // [])[]; type == "string" and length > 0))
      and (($value.addedPlanEntries |
        map({outputPath:.outputPath,type:.entry.type,tier:.entry.tier}) |
        sort_by([.outputPath,.type,.tier])) == expected_added_entries($gap_paths))
      and ($value.addedCrossLinks | type == "array" and length > 0)
      and $value.addedCrossLinks ==
        ($value.addedCrossLinks | sort_by([.reportedBy,.field,.target]))
      and (($value.addedCrossLinks | length) == ($value.addedCrossLinks | unique | length))
      and all($value.addedCrossLinks[]; . as $link |
        exact_keys($link; ["reportedBy","field","target"])
        and ($link.reportedBy | normalized_path(.))
        and ($link.field == "concepts" or $link.field == "algorithms")
        and ($link.target | normalized_path(.)))
      and $value.addedCrossLinks == expected_added_links($reports)
      and stored_entries_current($value; $live)
      and all($value.addedCrossLinks[]; . as $link |
        (plan_links($live) | index($link)) != null);
    def report($value):
      exact_keys($value; ["reportedBy","gaps"])
      and ($value.reportedBy | normalized_path(.))
      and ($value.gaps | type == "array" and length > 0)
      and all($value.gaps[];
        exact_keys(.; ["path","type","tier","reason"])
        and (.path | normalized_path(.))
        and (.reason | type == "string" and (gsub("[[:space:]]"; "") | length) > 0)
        and ((.type == "concept" and .tier == 2) or
          (.type == "algorithm" and .tier == 3)))
      and (($value.gaps | map([.path,.type,.tier]) | length) ==
        ($value.gaps | map([.path,.type,.tier]) | unique | length));
    def gap_tuples($reports):
      [$reports[] | .gaps[] | {path:.path,type:.type,tier:.tier}];
    def reports_consistent($reports):
      (gap_tuples($reports) | group_by(.path) |
        all(.[]; (map({type:.type,tier:.tier}) | unique | length) == 1));
    def derived_gap_paths($reports):
      gap_tuples($reports) | sort_by([.path,.type,.tier]) |
      unique_by([.path,.type,.tier]);
    def reports_valid($reports):
      ($reports | type == "array" and length > 0)
      and (($reports | map(.reportedBy) | length) ==
        ($reports | map(.reportedBy) | unique | length))
      and all($reports[]; report(.)) and reports_consistent($reports);
    def closed_record($value; $write; $live):
      exact_keys($value;
        ["status","reports","gapPaths","expectedScaffold","replayTier","requeued",
         "resetTiers","cleanedTiers","openedAt","planMutation","closedAt"])
      and $value.status == "cleared"
      and reports_valid($value.reports)
      and (($value.gapPaths | sort_by([.path,.type,.tier])) ==
        derived_gap_paths($value.reports))
      and all($value.gapPaths[]; . as $gap |
        ($gap.path | normalized_path(.)) and ($write.writeQueue | index($gap.path)) != null)
      and ($value.expectedScaffold | type == "object")
      and (($value.expectedScaffold | keys | sort) ==
        ($value.gapPaths | map(.path) | sort | unique))
      and all($value.expectedScaffold[]; sha256)
      and ($value.replayTier | type == "number")
      and ($value.replayTier | floor) == $value.replayTier
      and $value.replayTier >= 1 and $value.replayTier <= 6
      and $value.replayTier <= ($value.gapPaths | map(.tier) | min)
      and ($value.requeued | type == "array" and length > 0)
      and all($value.requeued[]; . as $path |
        ($path | normalized_path(.)) and ($write.writeQueue | index($path)) != null and
        ($write.provenance[$path].tier | type == "number" and floor == . and . >= 1 and . <= 6))
      and ($value.requeued | length) == ($value.requeued | unique | length)
      and all($value.reports[].reportedBy; . as $path | ($value.requeued | index($path)) != null)
      and all($value.requeued[];
        . as $path | ($value.gapPaths | map(.path) | index($path)) == null)
      and ($value.resetTiers | type == "array" and length > 0)
      and ($value.resetTiers == ($value.resetTiers | sort | unique))
      and all($value.resetTiers[]; type == "number" and floor == . and . >= 1 and . <= 6)
      and ($value.resetTiers ==
        ((($value.gapPaths | map(.tier)) +
          [$value.requeued[] as $path | $write.provenance[$path].tier]) | sort | unique))
      and ($value.resetTiers | index($value.replayTier)) != null
      and $value.cleanedTiers == $value.resetTiers
      and ($value.openedAt | timestamp) and ($value.closedAt | timestamp)
      and $value.closedAt >= $value.openedAt
      and mutation($value.planMutation; $value.reports; $value.gapPaths; $live);
    .[0] as $plan | .[1] as $write | .[2] as $live |
    if (exact_keys($plan;
        ["step","diffSummaryReady","diffSummaryHash","planFile","planHash","reviewFeedback","approved"])
      and $plan.step == "completed" and $plan.diffSummaryReady == true
      and ($plan.diffSummaryHash | sha256)
      and $plan.planFile == ".contributor-docs/doc-plan.yaml"
      and ($plan.planHash | sha256) and $plan.reviewFeedback == null and $plan.approved == true
      and exact_keys($write;
        ["step","authorizedPlanHash","scaffoldComplete","currentTier","tiersCompleted",
         "filesWritten","filesTotal","writeQueue","provenance","approvedOverwrites",
         "blockedCollisions","auditRepair","gapTransition","gapsResolved"])
      and ($write.authorizedPlanHash | sha256)
      and $write.gapTransition == null and ($write.gapsResolved | type == "array")
      and valid_plan($live)) | not
    then "PLAN_DRIFT_BLOCKED"
    elif (all($write.gapsResolved[]; closed_record(.; $write; $live)) and
      (($write.gapsResolved | map(.openedAt) | length) ==
       ($write.gapsResolved | map(.openedAt) | unique | length))) | not
    then "GAP_CLOSURE_INVALID"
    else
      (reduce $write.gapsResolved[] as $closed
        ({ok:true,cursor:$plan.planHash};
          if .ok and $closed.planMutation.fromPlanHash == .cursor
          then {ok:true,cursor:$closed.planMutation.toPlanHash}
          else {ok:false,cursor:.cursor} end)) as $walk |
      if $walk.ok and $walk.cursor == $write.authorizedPlanHash
        and $write.authorizedPlanHash == $expected and $actual == $expected
      then "OK" else "PLAN_DRIFT_BLOCKED" end
    end
  ' "$plan_state" "$write_state" <(yq -o=json '.' "$live_plan")); then
    echo "PLAN_DRIFT_BLOCKED: expected=${expected_hash} actual=${actual_hash}" >&2
    return 1
  fi
  if [[ $result != OK ]]; then
    echo "$result: expected=${expected_hash} actual=${actual_hash}" >&2
    return 1
  fi
}

# Close the state-agent-to-helper race for write-tier initialization. Plan identity is
# necessary but not sufficient: a collision or a changed current-tier slice does not
# change the plan hash, so the helper independently re-derives the exact pending input
# immediately before it creates or replaces processor state.
assert_processor_init_authority() {
  local expected_hash=$1 state_file=$2 files_json=$3
  local state_file_abs prefix suffix tier write_state

  assert_plan_authority "$expected_hash"
  state_file_abs=$(realpath -m -- "$state_file")
  prefix="$REPO_ROOT/.contributor-docs/write-tier-"
  suffix="/state.json"
  if [[ $state_file_abs != "$prefix"*"$suffix" ]]; then
    return 0
  fi
  tier=${state_file_abs#"$prefix"}
  tier=${tier%"$suffix"}
  write_state="$REPO_ROOT/.contributor-docs/write-state.json"
  if [[ ! $tier =~ ^[1-6]$ ]] || ! jq -e --argjson tier "$tier" --argjson files "$files_json" '
    ($files | type == "array") and
    (($files | length) == ($files | unique | length)) and
    all($files[]; type == "string" and length > 0) and
    .step == ("write_tier_" + ($tier | tostring)) and .currentTier == $tier and
    (.blockedCollisions | type == "array" and length == 0) and .gapTransition == null and
    ([.writeQueue[] as $path | .provenance[$path] as $entry |
      select($entry.tier == $tier and $entry.writeStatus == "pending") | $path] == $files)
  ' "$write_state" >/dev/null; then
    echo "PROCESSOR_AUTHORITY_INVALID: current tier, collision set, or pending slice changed" >&2
    return 1
  fi
}

if [[ ${1:-} == "--assert-plan-authority" ]]; then
  [[ $# -ge 2 ]] || {
    echo "❌ Usage: init-state.sh --assert-plan-authority <plan-hash> [plan-state] [write-state] [live-plan] [candidate-plan]" >&2
    exit 1
  }
  assert_plan_authority "$2" "${3:-}" "${4:-}" "${5:-}" "${6:-}"
  exit 0
fi

if [[ ${1:-} == "--check-write-contract" ]]; then
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
    write-writer-report-record
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
  assert_object_shape 'writer report' "$WRITE_PHASE" write-writer-report-record 5 gaps
  assert_object_shape 'writer report mirror' "$WRITE_AGENT" write-writer-report-record 5 gaps
  assert_object_shape 'gap transition' "$WRITE_PHASE" gap-transition-record 10 planMutation
  assert_object_shape 'gap transition mirror' "$WRITE_AGENT" gap-transition-record 10 planMutation
  assert_object_shape 'gap plan mutation' "$WRITE_PHASE" gap-plan-mutation-record 5 candidatePath
  assert_object_shape 'gap plan mutation mirror' "$WRITE_AGENT" gap-plan-mutation-record 5 candidatePath
  WRITE_SCHEMA_KEYS='["step","scaffoldComplete","currentTier","tiersCompleted","filesWritten","filesTotal","writeQueue","provenance","approvedOverwrites","blockedCollisions","auditRepair","gapTransition","gapsResolved","authorizedPlanHash"]'
  GAP_KEYS='["status","reports","gapPaths","expectedScaffold","replayTier","requeued","resetTiers","cleanedTiers","openedAt","planMutation"]'
  GAP_MUTATION_KEYS='["candidatePath","fromPlanHash","toPlanHash","addedPlanEntries","addedCrossLinks"]'
  WRITER_REPORT_KEYS='["reportedBy","authorizedPlanHash","authorizedFromHash","writtenHash","gaps"]'
  assert_exact_keys 'write state schema' "$WRITE_PHASE" write-state-schema "$WRITE_SCHEMA_KEYS"
  assert_exact_keys 'write state schema mirror' "$WRITE_AGENT" write-state-schema "$WRITE_SCHEMA_KEYS"
  assert_exact_keys 'gap transition' "$WRITE_PHASE" gap-transition-record "$GAP_KEYS"
  assert_exact_keys 'gap transition mirror' "$WRITE_AGENT" gap-transition-record "$GAP_KEYS"
  assert_exact_keys 'gap plan mutation' "$WRITE_PHASE" gap-plan-mutation-record "$GAP_MUTATION_KEYS"
  assert_exact_keys 'gap plan mutation mirror' "$WRITE_AGENT" gap-plan-mutation-record "$GAP_MUTATION_KEYS"
  assert_exact_keys 'writer report' "$WRITE_PHASE" write-writer-report-record "$WRITER_REPORT_KEYS"
  assert_exact_keys 'writer report mirror' "$WRITE_AGENT" write-writer-report-record "$WRITER_REPORT_KEYS"

  WRITER_REPORT_CONTRACT="$CONTROL_DIR/writer-report-contract.json"
  GAP_TRANSITION_CONTRACT="$CONTROL_DIR/gap-transition-contract.json"
  if ! extract_marked_json "$WRITE_PHASE" write-writer-report-record "$WRITER_REPORT_CONTRACT" ||
    ! extract_marked_json "$WRITE_PHASE" gap-transition-record "$GAP_TRANSITION_CONTRACT" ||
    ! cmp -s <(jq -cS '.gaps[0] | keys' "$WRITER_REPORT_CONTRACT") \
      <(jq -cS '.reports[0].gaps[0] | keys' "$GAP_TRANSITION_CONTRACT"); then
    contract_failure 'Writer-ledger gap shape drifted from transition report shape'
  fi

  GAP_MUTATION_CONTRACT="$CONTROL_DIR/gap-plan-mutation-contract.json"
  CANONICAL_CANDIDATE_PATH='.contributor-docs/doc-plan.gap-candidate.yaml'
  if ! extract_marked_json "$WRITE_PHASE" gap-plan-mutation-record "$GAP_MUTATION_CONTRACT" ||
    ! CONTRACT_CANDIDATE_PATH=$(jq -er '.candidatePath | select(type == "string")' "$GAP_MUTATION_CONTRACT"); then
    contract_failure 'Gap plan mutation candidate path is not extractable from the marked contract'
    CONTRACT_CANDIDATE_PATH=$CANONICAL_CANDIDATE_PATH
  elif [[ $CONTRACT_CANDIDATE_PATH != "$CANONICAL_CANDIDATE_PATH" ]]; then
    contract_failure "Gap plan mutation candidate path drifted: $CONTRACT_CANDIDATE_PATH"
  fi

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
	def sha256: type == "string" and test("^[0-9a-f]{64}$");
	def timestamp:
	  type == "string" and
	  test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$");
	def exact_keys($value; $want):
	  ($value | type == "object") and (($value | keys | sort) == ($want | sort));
	def normalized_path($value):
	  type == "string" and length > 0 and (startswith("/") | not) and
	  (split("/") | all(. != "" and . != "." and . != ".."));
	def expected_added_entries($gap_paths):
	  $gap_paths | map({outputPath:.path,type:.type,tier:.tier}) |
	  sort_by([.outputPath,.type,.tier]);
	def expected_added_links($reports):
	  [$reports[] as $report | $report.gaps[] |
	    {reportedBy:$report.reportedBy,
	     field:(if .type == "concept" then "concepts" else "algorithms" end),
	     target:.path}] |
	  sort_by([.reportedBy,.field,.target]) | unique_by([.reportedBy,.field,.target]);
	def stored_mutation($mutation; $candidate_path; $reports; $gap_paths):
	  exact_keys($mutation;
	    ["candidatePath","fromPlanHash","toPlanHash","addedPlanEntries","addedCrossLinks"])
	  and $mutation.candidatePath == $candidate_path
	  and ($mutation.fromPlanHash | sha256)
	  and ($mutation.toPlanHash | sha256)
	  and $mutation.fromPlanHash != $mutation.toPlanHash
	  and ($mutation.addedPlanEntries | type == "array" and length > 0)
	  and $mutation.addedPlanEntries == ($mutation.addedPlanEntries | sort_by(.outputPath))
	  and (($mutation.addedPlanEntries | map(.outputPath) | length) ==
	    ($mutation.addedPlanEntries | map(.outputPath) | unique | length))
	  and all($mutation.addedPlanEntries[]; . as $added |
	    exact_keys($added; ["outputPath","container","entry"])
	    and ($added.outputPath | normalized_path(.))
	    and ($added.container | type == "string" and
	      test("^(shared|topLevel|adrs|indexes|module:[^/]+)$"))
	    and ($added.entry | type == "object")
	    and ((["path","type","tier","description","sources"] -
	      ($added.entry | keys)) | length == 0)
	    and (((($added.entry | keys) -
	      ["path","type","conceptType","tier","description","sources","crossLinks","tags"]) |
	      length) == 0)
	    and ($added.entry.path | normalized_path(.))
	    and ($added.outputPath | endswith("/" + $added.entry.path))
	    and (($added.entry.type == "concept" and $added.entry.tier == 2) or
	      ($added.entry.type == "algorithm" and $added.entry.tier == 3))
	    and ($added.entry.description | type == "string" and
	      (gsub("[[:space:]]"; "") | length) > 0)
	    and ($added.entry.sources | type == "array" and length > 0)
	    and all($added.entry.sources[]; type == "string" and length > 0)
	    and (($added.entry.conceptType // "") | type == "string")
	    and (($added.entry.crossLinks // {}) | type == "object")
	    and all(($added.entry.crossLinks // {})[]; type == "array" and
	      all(.[]; type == "string" and length > 0))
	    and (($added.entry.tags // []) | type == "array")
	    and all(($added.entry.tags // [])[]; type == "string" and length > 0))
	  and (($mutation.addedPlanEntries |
	    map({outputPath:.outputPath,type:.entry.type,tier:.entry.tier}) |
	    sort_by([.outputPath,.type,.tier])) == expected_added_entries($gap_paths))
	  and ($mutation.addedCrossLinks | type == "array" and length > 0)
	  and $mutation.addedCrossLinks ==
	    ($mutation.addedCrossLinks | sort_by([.reportedBy,.field,.target]))
	  and (($mutation.addedCrossLinks | length) ==
	    ($mutation.addedCrossLinks | unique | length))
	  and all($mutation.addedCrossLinks[]; . as $link |
	    exact_keys($link; ["reportedBy","field","target"])
	    and ($link.reportedBy | normalized_path(.))
	    and ($link.field == "concepts" or $link.field == "algorithms")
	    and ($link.target | normalized_path(.)))
	  and $mutation.addedCrossLinks == expected_added_links($reports);
	def gap_item($gap):
	  exact_keys($gap; ["path","type","tier","reason"])
	  and ($gap.path | normalized_path(.))
	  and ($gap.reason | type == "string" and (gsub("[[:space:]]"; "") | length) > 0)
	  and (($gap.type == "concept" and $gap.tier == 2) or
	    ($gap.type == "algorithm" and $gap.tier == 3));
	def writer_report($report; $path; $authorized; $written):
	  exact_keys($report;
	    ["reportedBy","authorizedPlanHash","authorizedFromHash","writtenHash","gaps"])
	  and $report.reportedBy == $path
	  and $report.authorizedPlanHash == $authorized
	  and ($report.authorizedFromHash | sha256)
	  and $report.writtenHash == $written and ($report.writtenHash | sha256)
	  and ($report.gaps | type == "array")
	  and all($report.gaps[]; gap_item(.))
	  and (($report.gaps | map([.path,.type,.tier]) | length) ==
	    ($report.gaps | map([.path,.type,.tier]) | unique | length))
	  and ($report.gaps | group_by(.path) |
	    all(.[]; (map({type:.type,tier:.tier}) | unique | length) == 1));
	def ledger_reports($state):
	  [$state.writeQueue[] as $path | $state.provenance[$path] as $entry |
	    select($entry.tier == $state.currentTier and $entry.writeStatus == "written") |
	    if writer_report($entry.writerReport; $path; $state.authorizedPlanHash; $entry.writtenHash)
	    then select(($entry.writerReport.gaps | length) > 0) |
	      {reportedBy:$path,gaps:$entry.writerReport.gaps}
	    else refuse("WRITE_REPORT_MISSING") end] | sort_by(.reportedBy);
	def reported_gap_tuples($reports):
	  [$reports[] | .gaps[] | {path:.path, type:.type, tier:.tier}];
	def derived_gap_paths($reports):
	  reported_gap_tuples($reports) | sort_by([.path,.type,.tier]) |
	  unique_by([.path,.type,.tier]);
	def reports_consistent($reports):
	  (reported_gap_tuples($reports) | group_by(.path) |
	    all(.[]; (map({type:.type,tier:.tier}) | unique | length) == 1));
	def reports_valid($reports):
	  ($reports | type == "array") and ($reports | length) > 0 and
	  (($reports | map(.reportedBy) | length) == ($reports | map(.reportedBy) | unique | length)) and
	  all($reports[];
	    exact_keys(.; ["reportedBy","gaps"])
	    and (.reportedBy | type == "string" and length > 0)
	    and (.gaps | type == "array" and length > 0)
	    and all(.gaps[]; gap_item(.))
	    and ((.gaps | map([.path,.type,.tier]) | length) ==
	      (.gaps | map([.path,.type,.tier]) | unique | length))) and
	  reports_consistent($reports);
	def closed_record($closed; $state):
	  exact_keys($closed;
	    ["status","reports","gapPaths","expectedScaffold","replayTier","requeued",
	     "resetTiers","cleanedTiers","openedAt","planMutation","closedAt"])
	  and $closed.status == "cleared"
	  and reports_valid($closed.reports)
	  and (($closed.gapPaths | sort_by([.path,.type,.tier])) ==
	    derived_gap_paths($closed.reports))
	  and all($closed.gapPaths[]; . as $gap |
	    ($gap.path | normalized_path(.)) and ($state.writeQueue | index($gap.path)) != null)
	  and ($closed.expectedScaffold | type == "object")
	  and (($closed.expectedScaffold | keys | sort) ==
	    ($closed.gapPaths | map(.path) | sort | unique))
	  and all($closed.expectedScaffold[]; sha256)
	  and ($closed.replayTier | type == "number") and ($closed.replayTier | floor) == $closed.replayTier
	  and $closed.replayTier >= 1 and $closed.replayTier <= 6
	  and $closed.replayTier <= ($closed.gapPaths | map(.tier) | min)
	  and ($closed.requeued | type == "array" and length > 0)
	  and all($closed.requeued[]; . as $path |
	    ($path | normalized_path(.)) and ($state.writeQueue | index($path)) != null and
	    ($state.provenance[$path].tier | type == "number" and floor == . and . >= 1 and . <= 6))
	  and ($closed.requeued | length) == ($closed.requeued | unique | length)
	  and all($closed.reports[].reportedBy; . as $path | ($closed.requeued | index($path)) != null)
	  and all($closed.requeued[];
	    . as $path | ($closed.gapPaths | map(.path) | index($path)) == null)
	  and ($closed.resetTiers | type == "array" and length > 0)
	  and $closed.resetTiers == ($closed.resetTiers | sort | unique)
	  and all($closed.resetTiers[]; type == "number" and floor == . and . >= 1 and . <= 6)
	  and ($closed.resetTiers ==
	    ((($closed.gapPaths | map(.tier)) +
	      [$closed.requeued[] as $path | $state.provenance[$path].tier]) | sort | unique))
	  and ($closed.resetTiers | index($closed.replayTier)) != null
	  and $closed.cleanedTiers == $closed.resetTiers
	  and ($closed.openedAt | timestamp) and ($closed.closedAt | timestamp)
	  and $closed.closedAt >= $closed.openedAt
	  and stored_mutation($closed.planMutation; $state.canonicalCandidatePath;
	    $closed.reports; $closed.gapPaths);
	def closed_cursor($state):
	  if ($state.planStateHash | sha256) and
	    ($state.approvedPlanHash | sha256) and
	    $state.approvedPlanHash == $state.planStateHash and
	    ($state.gapsResolved | type == "array") and
	    ($state.canonicalCandidatePath | type == "string") then
	    if (all($state.gapsResolved[]; closed_record(.; $state)) and
	      (($state.gapsResolved | map(.openedAt) | length) ==
	       ($state.gapsResolved | map(.openedAt) | unique | length))) | not
	    then refuse("GAP_CLOSURE_INVALID")
	    else reduce $state.gapsResolved[] as $closed
	      ($state.planStateHash;
	        if $closed.planMutation.fromPlanHash == . then $closed.planMutation.toPlanHash
	        else refuse("PLAN_DRIFT_BLOCKED") end)
	    end
	  else refuse("PLAN_DRIFT_BLOCKED") end;
	def current_plan($state):
	  closed_cursor($state) as $cursor |
	  if $state.gapStatus == null and
	    $state.authorizedPlanHash == $cursor and
	    $state.livePlanHash == $state.authorizedPlanHash and
	    ($state.candidateHash // null) == null then
	    $state
	  elif (["planned","prepared","scaffolded","reset","cleaned"] | index($state.gapStatus)) != null and
	    stored_mutation($state.gapPlanMutation; $state.canonicalCandidatePath;
	      $state.gapRecord.reports; $state.gapRecord.gapPaths) and
	    $state.gapPlanMutation.fromPlanHash == $cursor and
	    $state.authorizedPlanHash == $state.gapPlanMutation.toPlanHash and
	    $state.livePlanHash == $state.authorizedPlanHash and
	    ($state.candidateHash // null) == null then
	    $state
	  else refuse("PLAN_DRIFT_BLOCKED") end;
	def parse_plan($bytes): try ($bytes | fromjson) catch refuse("GAP_PLAN_DELTA_INVALID");
	def valid_plan($plan):
	  exact_keys($plan; ["docsRoot","modules","shared","topLevel","adrs","indexes"])
	  and ($plan.docsRoot | type == "string" and length > 0)
	  and ($plan.modules | type == "array")
	  and all($plan.modules[];
	    exact_keys(.; ["name","description","files"])
	    and (.name | type == "string" and length > 0)
	    and (.description | type == "string") and (.files | type == "array"))
	  and exact_keys($plan.shared; ["files"]) and ($plan.shared.files | type == "array")
	  and ($plan.topLevel | type == "array")
	  and ($plan.adrs | type == "array") and ($plan.indexes | type == "array");
	def plan_entries($plan):
	  ([ $plan.modules[] as $module | $module.files[] as $entry |
	      {outputPath:($plan.docsRoot + "/" + $entry.path),
	       container:("module:" + $module.name),entry:$entry} ]
	   + [ $plan.shared.files[] as $entry |
	      {outputPath:($plan.docsRoot + "/" + $entry.path),container:"shared",entry:$entry} ]
	   + [ $plan.topLevel[] as $entry |
	      {outputPath:($plan.docsRoot + "/" + $entry.path),container:"topLevel",entry:$entry} ]
	   + [ $plan.adrs[] as $entry |
	      {outputPath:($plan.docsRoot + "/" + $entry.path),container:"adrs",entry:$entry} ]
	   + [ $plan.indexes[] as $entry |
	      {outputPath:($plan.docsRoot + "/" + $entry.path),container:"indexes",entry:$entry} ]);
	def plan_skeleton($plan):
	  $plan | .modules = [.modules[] | .files = []] | .shared.files = [] |
	  .topLevel = [] | .adrs = [] | .indexes = [];
	def plan_links($plan):
	  [plan_entries($plan)[] as $wrapped |
	    (($wrapped.entry.crossLinks // {}) | to_entries[]) as $links |
	    $links.value[] as $target |
	    {reportedBy:$wrapped.outputPath,field:$links.key,
	     target:($plan.docsRoot + "/" + $target)}] |
	  sort_by([.reportedBy,.field,.target]) | unique_by([.reportedBy,.field,.target]);
	def strip_added_links($wrapped; $added_links; $docs_root):
	  reduce ($added_links[] | select(.reportedBy == $wrapped.outputPath)) as $link
	    ($wrapped;
	      .entry.crossLinks[$link.field] = ((.entry.crossLinks[$link.field] // []) |
	        map(select(($docs_root + "/" + .) != $link.target))));
	def derive_mutation($state; $data; $reports; $gap_paths):
	  parse_plan($data.livePlanBytes) as $live |
	  parse_plan($data.candidatePlanBytes) as $candidate |
	  if (valid_plan($live) and valid_plan($candidate)) | not
	  then refuse("GAP_PLAN_DELTA_INVALID")
	  else
	    (plan_entries($live) | sort_by(.outputPath)) as $live_entries |
	    (plan_entries($candidate) | sort_by(.outputPath)) as $candidate_entries |
	    ($live_entries | map(.outputPath)) as $live_paths |
	    ($candidate_entries | map(.outputPath)) as $candidate_paths |
	    ($candidate_entries |
	      map(. as $entry | select(($live_paths | index($entry.outputPath)) == null))) as $added_entries |
	    (plan_links($live)) as $live_links |
	    (plan_links($candidate)) as $candidate_links |
	    ($candidate_links |
	      map(. as $link | select(($live_links | index($link)) == null))) as $added_links |
	    ($candidate_entries |
	      map(. as $entry | select(($live_paths | index($entry.outputPath)) != null) |
	        strip_added_links($entry; $added_links; $candidate.docsRoot)) |
	      sort_by(.outputPath)) as $stripped_candidate_entries |
	    if $live.docsRoot != $candidate.docsRoot
	      or (plan_skeleton($live) != plan_skeleton($candidate))
	      or (($live_paths | length) != ($live_paths | unique | length))
	      or (($candidate_paths | length) != ($candidate_paths | unique | length))
	      or ($live_paths | any(. as $path | ($candidate_paths | index($path)) == null))
	      or ($stripped_candidate_entries != $live_entries)
	      or (($added_entries |
	        map({outputPath:.outputPath,type:.entry.type,tier:.entry.tier}) |
	        sort_by([.outputPath,.type,.tier])) != expected_added_entries($gap_paths))
	      or (($added_links | sort_by([.reportedBy,.field,.target])) != expected_added_links($reports))
	    then refuse("GAP_PLAN_DELTA_INVALID")
	    else {
	      candidatePath:$state.canonicalCandidatePath,
	      fromPlanHash:$state.livePlanHash,
	      toPlanHash:$state.candidateHash,
	      addedPlanEntries:($added_entries | sort_by(.outputPath)),
	      addedCrossLinks:($added_links | sort_by([.reportedBy,.field,.target]))
	    } end
	  end;
	def gap_mutation($state): $state.gapPlanMutation;
	def apply($state; $operation; $data):
	  if $operation == "authorize-gap-plan" then
	    closed_cursor($state) as $cursor |
	    ledger_reports($state) as $reports |
	    derived_gap_paths($reports) as $gap_paths |
	    if $state.gapStatus != null then refuse("GAP_TRANSITION_INVALID")
	    elif ($data | type) != "object" or ($data | has("reports")) or ($data | has("gapPaths"))
	      then refuse("GAP_REPORT_SET_INVALID")
	    elif (exact_keys($data; ["livePlanBytes","candidatePlanBytes","openedAt"]) | not)
	      then refuse("GAP_PLAN_DELTA_INVALID")
	    elif $state.canonicalCandidatePath != ".contributor-docs/doc-plan.gap-candidate.yaml"
	      then refuse("GAP_PLAN_DELTA_INVALID")
	    elif $state.authorizedPlanHash != $cursor or
	      $state.livePlanHash != $state.authorizedPlanHash then refuse("PLAN_DRIFT_BLOCKED")
	    elif ($state.candidateHash // null) == null then refuse("GAP_PLAN_CANDIDATE_MISSING")
	    elif (reports_valid($reports) | not) then refuse("GAP_REPORT_SET_INVALID")
	    elif ($data.openedAt | timestamp | not) then refuse("GAP_TRANSITION_INVALID")
	    else derive_mutation($state; $data; $reports; $gap_paths) as $mutation |
	      if $mutation.fromPlanHash != $cursor or
	        $state.candidateHash != $mutation.toPlanHash then refuse("GAP_PLAN_HASH_INVALID")
	      else $state | .gapStatus = "enqueued" | .gapPlanMutation = $mutation |
	        .gapRecord = {
	          status:"enqueued",reports:$reports,gapPaths:$gap_paths,
	          expectedScaffold:{},replayTier:($gap_paths | map(.tier) | min),
	          requeued:($reports | map(.reportedBy) | sort | unique),
	          resetTiers:((($gap_paths | map(.tier)) + [$state.currentTier]) | sort | unique),
	          cleanedTiers:[],openedAt:$data.openedAt,planMutation:$mutation
	        }
	      end
	    end
  elif $operation == "apply-gap-plan" then
    closed_cursor($state) as $cursor |
    if $state.gapStatus == "planned" and
      stored_mutation(gap_mutation($state); $state.canonicalCandidatePath;
        $state.gapRecord.reports; $state.gapRecord.gapPaths) and
      gap_mutation($state).fromPlanHash == $cursor and
      $state.authorizedPlanHash == gap_mutation($state).toPlanHash and
      $state.authorizedPlanHash == $state.livePlanHash and
      ($state.candidateHash // null) == null then $state
    elif $state.gapStatus != "enqueued" then refuse("GAP_TRANSITION_INVALID")
    elif (stored_mutation(gap_mutation($state); $state.canonicalCandidatePath;
      $state.gapRecord.reports; $state.gapRecord.gapPaths) | not) then
      refuse("GAP_PLAN_HASH_INVALID")
    elif gap_mutation($state).fromPlanHash != $cursor or
      $state.authorizedPlanHash != $cursor then refuse("PLAN_DRIFT_BLOCKED")
    elif $state.livePlanHash == gap_mutation($state).fromPlanHash and
      ($state.candidateHash // null) == null then refuse("GAP_PLAN_CANDIDATE_MISSING")
    elif $state.livePlanHash == gap_mutation($state).fromPlanHash and
      $state.candidateHash != gap_mutation($state).toPlanHash then refuse("GAP_PLAN_HASH_INVALID")
	    elif $state.livePlanHash == gap_mutation($state).fromPlanHash and
	      $state.candidateHash == gap_mutation($state).toPlanHash then
	      $state | .livePlanHash = gap_mutation($state).toPlanHash |
	        .authorizedPlanHash = gap_mutation($state).toPlanHash |
	        .candidateHash = null | .gapStatus = "planned" | .gapRecord.status = "planned"
	    elif $state.livePlanHash == gap_mutation($state).toPlanHash and
	      ($state.candidateHash // null) == null then
	      $state | .authorizedPlanHash = gap_mutation($state).toPlanHash |
	        .gapStatus = "planned" | .gapRecord.status = "planned"
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
	    elif any($state.writeQueue[];
	      . as $path | $state.provenance[$path] as $entry |
	      $entry.tier == $state.currentTier and $entry.writeStatus != "written")
	      then refuse("WRITE_INCOMPLETE")
	    elif any($state.writeQueue[];
	      . as $path | $state.provenance[$path] as $entry |
	      $entry.tier == $state.currentTier and $entry.writeStatus == "written" and
	      (writer_report($entry.writerReport; $path; $state.authorizedPlanHash; $entry.writtenHash) | not))
	      then refuse("WRITE_REPORT_MISSING")
	    else $state | .step = "completed" end
	  elif $operation == "record-write" then
	    current_plan($state) |
	    if $data.returnedHash != $data.diskHash then refuse("WRITE_HASH_MISMATCH")
	    elif ($data.path | type != "string") or (($state.writeQueue | index($data.path)) == null) or
	      ($state.provenance[$data.path] == null) or
	      $state.provenance[$data.path].writeStatus != "pending" then refuse("WRITE_INCOMPLETE")
	    elif (writer_report($data.writerReport; $data.path; $state.authorizedPlanHash; $data.diskHash) | not)
	      then refuse("GAP_REPORT_SET_INVALID")
	    else $state |
	      .provenance[$data.path].writeStatus = "written" |
	      .provenance[$data.path].writtenHash = $data.diskHash |
	      .provenance[$data.path].writerReport = $data.writerReport |
	      .pending -= [$data.path]
	    end
  elif $operation == "gap-advance" then
    if $state.gapStatus == "enqueued" then refuse("GAP_TRANSITION_INVALID")
    else current_plan($state) |
    if next_gap($state.gapStatus) != $data.target then refuse("GAP_TRANSITION_INVALID")
	    elif $data.target == "prepared" and
	      ((($data.expectedScaffold | type) != "object") or
	       (($data.expectedScaffold | keys | sort) !=
	        ($state.gapRecord.gapPaths | map(.path) | sort | unique)) or
	       (all($data.expectedScaffold[]; sha256) | not))
	      then refuse("GAP_MANIFEST_INVALID")
	    elif $data.target == "cleaned" and
	      (($data.cleanedTiers | sort) != ($state.gapRecord.resetTiers | sort))
	      then refuse("GAP_CLEANUP_INCOMPLETE")
	    elif $data.target == "cleared" then
	      if ($data.closedAt | timestamp | not) or $data.closedAt < $state.gapRecord.openedAt
	      then refuse("GAP_CLOSURE_INVALID")
	      elif ($state.gapRecord.cleanedTiers != $state.gapRecord.resetTiers)
	      then refuse("GAP_CLEANUP_INCOMPLETE")
	      else (.gapRecord + {status:"cleared",closedAt:$data.closedAt}) as $closed |
	      if (closed_record($closed; $state) | not)
	      then refuse("GAP_CLOSURE_INVALID")
	      elif any($state.gapsResolved[]; .openedAt == $closed.openedAt)
	      then if any($state.gapsResolved[]; . == $closed)
	        then $state | .gapPlanMutation = null | .gapRecord = null | .gapStatus = null
	        else refuse("GAP_CLOSURE_INVALID") end
	      else $state |
	        .gapsResolved += [$closed] |
	        .gapPlanMutation = null | .gapRecord = null | .gapStatus = null
	      end end
	    else $state | .gapStatus = $data.target | .gapRecord.status = $data.target |
	      if $data.target == "prepared" then .gapRecord.expectedScaffold = $data.expectedScaffold
	      elif $data.target == "scaffolded" then
	        reduce .gapRecord.gapPaths[] as $gap (.;
	          .writeQueue += [$gap.path] |
	          .provenance[$gap.path] = {
	            tier:$gap.tier,writeStatus:"pending",
	            scaffoldHash:.gapRecord.expectedScaffold[$gap.path],
	            writtenHash:null,writerReport:null
	          })
	      elif $data.target == "reset" then
	        reduce .gapRecord.requeued[] as $path (.;
	          .provenance[$path].writeStatus = "pending" |
	          .provenance[$path].writerReport = null)
	      elif $data.target == "cleaned" then .gapRecord.cleanedTiers = $data.cleanedTiers
	      else . end
	    end end
  else refuse("UNKNOWN_OPERATION") end;
apply($state; $operation; $data)
JQ

  LIVE_PLAN_BYTES=$(jq -cn '{
	    docsRoot:"docs",
	    modules:[{name:"orders",description:"Order documentation",files:[{
	      path:"r.mdx",type:"feature",tier:4,description:"Reporter",
	      sources:["src/r.ts"],crossLinks:{concepts:[],algorithms:[]},tags:["orders"]
	    }]}],
	    shared:{files:[]},topLevel:[],adrs:[],indexes:[]
	  }')
  CANDIDATE_PLAN_BYTES=$(jq -cn '{
	    docsRoot:"docs",
	    modules:[{name:"orders",description:"Order documentation",files:[{
	      path:"r.mdx",type:"feature",tier:4,description:"Reporter",
	      sources:["src/r.ts"],crossLinks:{concepts:["a.mdx"],algorithms:[]},tags:["orders"]
	    }]}],
	    shared:{files:[{
	      path:"a.mdx",type:"concept",tier:2,description:"Reporter needs the concept",
	      sources:["src/r.ts"],crossLinks:{concepts:[],algorithms:[]},tags:["orders"]
	    }]},topLevel:[],adrs:[],indexes:[]
	  }')
  UNRELATED_PLAN_BYTES=$(jq -c '.modules[0].files[0].sources += ["src/unrelated.ts"]' \
    <<<"$CANDIDATE_PLAN_BYTES")
  SECOND_PLAN_BYTES=$(jq -c '
	    .modules[0].files[0].crossLinks.algorithms = ["b.mdx"] |
	    .shared.files += [{
	      path:"b.mdx",type:"algorithm",tier:3,description:"Reporter needs the algorithm",
	      sources:["src/r.ts"],crossLinks:{concepts:[],algorithms:[]},tags:["orders"]
	    }]
	  ' <<<"$CANDIDATE_PLAN_BYTES")
  PLAN_A=$(printf '%s' "$LIVE_PLAN_BYTES" | sha256sum | cut -d ' ' -f1)
  PLAN_B=$(printf '%s' "$CANDIDATE_PLAN_BYTES" | sha256sum | cut -d ' ' -f1)
  PLAN_C=$(printf '%s' "$SECOND_PLAN_BYTES" | sha256sum | cut -d ' ' -f1)
  UNRELATED_HASH=$(printf '%s' "$UNRELATED_PLAN_BYTES" | sha256sum | cut -d ' ' -f1)
  FILE_BYTES='complete writer output'
  FILE_HASH=$(printf '%s' "$FILE_BYTES" | sha256sum | cut -d ' ' -f1)
  FROM_HASH=eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee
  SCAFFOLD_A=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
  SCAFFOLD_B=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
  BASE_STATE=$(jq -cn --arg hash "$PLAN_A" --arg fileHash "$FILE_HASH" \
    --arg fromHash "$FROM_HASH" --arg candidate "$CONTRACT_CANDIDATE_PATH" '{
	      step:"scaffold",pending:[],writeQueue:["docs/r.mdx"],currentTier:4,gapStatus:null,
	      planStateHash:$hash,approvedPlanHash:$hash,authorizedPlanHash:$hash,livePlanHash:$hash,
	      candidateHash:null,canonicalCandidatePath:$candidate,gapsResolved:[],
	      gapPlanMutation:null,gapRecord:null,
	      provenance:{"docs/r.mdx":{
	        tier:4,writeStatus:"written",scaffoldHash:$fromHash,writtenHash:$fileHash,
	        writerReport:{reportedBy:"docs/r.mdx",authorizedPlanHash:$hash,
	          authorizedFromHash:$fromHash,writtenHash:$fileHash,gaps:[{
	            path:"docs/a.mdx",type:"concept",tier:2,reason:"Reporter needs the concept"
	          }]}
	      }}
	    }')
  STORED_PLAN_MUTATION=$(jq -cn --arg from "$PLAN_A" --arg to "$PLAN_B" \
    --arg candidate "$CONTRACT_CANDIDATE_PATH" --argjson plan "$CANDIDATE_PLAN_BYTES" '{
	      fromPlanHash:$from,toPlanHash:$to,candidatePath:$candidate,
	      addedPlanEntries:[{outputPath:"docs/a.mdx",container:"shared",entry:$plan.shared.files[0]}],
	      addedCrossLinks:[{reportedBy:"docs/r.mdx",field:"concepts",target:"docs/a.mdx"}]
	    }')
  SECOND_STORED_MUTATION=$(jq -cn --arg from "$PLAN_B" --arg to "$PLAN_C" \
    --arg candidate "$CONTRACT_CANDIDATE_PATH" --argjson plan "$SECOND_PLAN_BYTES" '{
	      fromPlanHash:$from,toPlanHash:$to,candidatePath:$candidate,
	      addedPlanEntries:[{outputPath:"docs/b.mdx",container:"shared",entry:$plan.shared.files[1]}],
	      addedCrossLinks:[{reportedBy:"docs/r.mdx",field:"algorithms",target:"docs/b.mdx"}]
	    }')
  GAP_RECORD=$(jq -cn --argjson mutation "$STORED_PLAN_MUTATION" '{
	    status:"enqueued",
	    reports:[{reportedBy:"docs/r.mdx",gaps:[{
	      path:"docs/a.mdx",type:"concept",tier:2,reason:"Reporter needs the concept"
	    }]}],
	    gapPaths:[{path:"docs/a.mdx",type:"concept",tier:2}],expectedScaffold:{},
	    replayTier:2,requeued:["docs/r.mdx"],resetTiers:[2,4],cleanedTiers:[],
	    openedAt:"2026-08-01T00:00:00Z",planMutation:$mutation
	  }')
  PLAN_INPUT=$(jq -cn --arg live "$LIVE_PLAN_BYTES" --arg candidate "$CANDIDATE_PLAN_BYTES" '{
	    livePlanBytes:$live,candidatePlanBytes:$candidate,openedAt:"2026-08-01T00:00:00Z"
	  }')
  SECOND_PLAN_INPUT=$(jq -cn --arg live "$CANDIDATE_PLAN_BYTES" --arg candidate "$SECOND_PLAN_BYTES" '{
	    livePlanBytes:$live,candidatePlanBytes:$candidate,openedAt:"2026-08-01T00:01:00Z"
	  }')
  UNRELATED_INPUT=$(jq -cn --arg live "$LIVE_PLAN_BYTES" --arg candidate "$UNRELATED_PLAN_BYTES" '{
	    livePlanBytes:$live,candidatePlanBytes:$candidate,openedAt:"2026-08-01T00:00:00Z"
	  }')
  CLOSED_RECORD_AB=$(jq -cn --argjson mutation "$STORED_PLAN_MUTATION" \
    --arg scaffold "$SCAFFOLD_A" '{
	      status:"cleared",reports:[{reportedBy:"docs/r.mdx",gaps:[{
	        path:"docs/a.mdx",type:"concept",tier:2,reason:"Reporter needs the concept"
	      }]}],gapPaths:[{path:"docs/a.mdx",type:"concept",tier:2}],
	      expectedScaffold:{"docs/a.mdx":$scaffold},replayTier:2,requeued:["docs/r.mdx"],
	      resetTiers:[2,4],cleanedTiers:[2,4],openedAt:"2026-08-01T00:00:00Z",
	      planMutation:$mutation,closedAt:"2026-08-01T00:00:01Z"
	    }')
  CLOSED_RECORD_BC=$(jq -cn --argjson mutation "$SECOND_STORED_MUTATION" \
    --arg scaffold "$SCAFFOLD_B" '{
	      status:"cleared",reports:[{reportedBy:"docs/r.mdx",gaps:[{
	        path:"docs/b.mdx",type:"algorithm",tier:3,reason:"Reporter needs the algorithm"
	      }]}],gapPaths:[{path:"docs/b.mdx",type:"algorithm",tier:3}],
	      expectedScaffold:{"docs/b.mdx":$scaffold},replayTier:3,requeued:["docs/r.mdx"],
	      resetTiers:[3,4],cleanedTiers:[3,4],openedAt:"2026-08-01T00:01:00Z",
	      planMutation:$mutation,closedAt:"2026-08-01T00:01:01Z"
	    }')
  ENQUEUED_STATE=$(jq -c --arg hash "$PLAN_B" --argjson mutation "$STORED_PLAN_MUTATION" \
    --argjson record "$GAP_RECORD" '
	      .candidateHash = $hash | .gapStatus = "enqueued" | .gapPlanMutation = $mutation |
	      .gapRecord = $record
	    ' <<<"$BASE_STATE")
  PLANNED_STATE=$(jq -c --arg hash "$PLAN_B" '
	    .candidateHash = null | .authorizedPlanHash = $hash | .livePlanHash = $hash |
	    .gapStatus = "planned" | .gapRecord.status = "planned"
	  ' <<<"$ENQUEUED_STATE")

  if OUTPUT=$(jq -n -L "$CONTROL_DIR" --argjson state "$BASE_STATE" \
    --arg operation create-scaffold --argjson data '{}' -f "$CONTROL_DIR/reducer.jq" 2>&1); then
    echo "❌ Create-before-prepare control passed" >&2
    FAILURES=$((FAILURES + 1))
  elif [[ $OUTPUT != *SCAFFOLD_NOT_PREPARED* ]]; then
    echo "❌ Create-before-prepare failed for the wrong reason" >&2
    FAILURES=$((FAILURES + 1))
  fi
  PENDING_STATE=$(jq -c '.step = "write_tier_6" | .pending = ["docs/a.mdx"]' <<<"$BASE_STATE")
  if OUTPUT=$(jq -n -L "$CONTROL_DIR" \
    --argjson state "$PENDING_STATE" \
    --arg operation complete-tier --argjson data '{}' -f "$CONTROL_DIR/reducer.jq" 2>&1); then
    echo "❌ Pending-completion control passed" >&2
    FAILURES=$((FAILURES + 1))
  elif [[ $OUTPUT != *WRITE_INCOMPLETE* ]]; then
    echo "❌ Pending-completion failed for the wrong reason" >&2
    FAILURES=$((FAILURES + 1))
  fi
  if OUTPUT=$(jq -n -L "$CONTROL_DIR" \
    --argjson state "$ENQUEUED_STATE" \
    --arg operation gap-advance --argjson data '{"target":"prepared"}' \
    -f "$CONTROL_DIR/reducer.jq" 2>&1); then
    echo "❌ Skipped-gap-status control passed" >&2
    FAILURES=$((FAILURES + 1))
  elif [[ $OUTPUT != *GAP_TRANSITION_INVALID* ]]; then
    echo "❌ Skipped-gap-status failed for the wrong reason" >&2
    FAILURES=$((FAILURES + 1))
  fi
  if OUTPUT=$(jq -n -L "$CONTROL_DIR" \
    --argjson state "$(jq -c '.step = "write_tier_2"' <<<"$PLANNED_STATE")" \
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
    --argjson state "$(jq -c '.step = "write_tier_2" | .gapStatus = "reset"' <<<"$PLANNED_STATE")" \
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
    --argjson state "$(jq -c '.step = "write_tier_2" | .pending = ["docs/a.mdx"]' <<<"$BASE_STATE")" \
    --arg operation record-write \
    --argjson data '{"returnedHash":"aa","diskHash":"bb"}' \
    -f "$CONTROL_DIR/reducer.jq" 2>&1); then
    echo "❌ Writer-hash-mismatch control passed" >&2
    FAILURES=$((FAILURES + 1))
  elif [[ $OUTPUT != *WRITE_HASH_MISMATCH* ]]; then
    echo "❌ Writer-hash-mismatch failed for the wrong reason" >&2
    FAILURES=$((FAILURES + 1))
  fi

  PENDING_WRITE_STATE=$(jq -c '
    .step = "write_tier_4" | .pending = ["docs/r.mdx"] |
    .provenance["docs/r.mdx"].writeStatus = "pending" |
    .provenance["docs/r.mdx"].writerReport = null
  ' <<<"$BASE_STATE")
  WRITE_REPORT_NONE=$(jq -cn --arg plan "$PLAN_A" --arg from "$FROM_HASH" \
    --arg written "$FILE_HASH" '{
      reportedBy:"docs/r.mdx",authorizedPlanHash:$plan,authorizedFromHash:$from,
      writtenHash:$written,gaps:[]
    }')
  WRITE_REPORT_VALID=$(jq -cn --arg plan "$PLAN_A" --arg from "$FROM_HASH" \
    --arg written "$FILE_HASH" '{
      reportedBy:"docs/r.mdx",authorizedPlanHash:$plan,authorizedFromHash:$from,
      writtenHash:$written,gaps:[{
        path:"docs/a.mdx",type:"concept",tier:2,reason:"Reporter needs the concept"
      }]
    }')
  WRITE_DATA_NONE=$(jq -cn --arg hash "$FILE_HASH" --argjson report "$WRITE_REPORT_NONE" '{
    path:"docs/r.mdx",returnedHash:$hash,diskHash:$hash,writerReport:$report
  }')
  WRITE_DATA_VALID=$(jq -cn --arg hash "$FILE_HASH" --argjson report "$WRITE_REPORT_VALID" '{
    path:"docs/r.mdx",returnedHash:$hash,diskHash:$hash,writerReport:$report
  }')
  if ! WRITTEN_NONE=$(jq -n -L "$CONTROL_DIR" --argjson state "$PENDING_WRITE_STATE" \
    --arg operation record-write --argjson data "$WRITE_DATA_NONE" -f "$CONTROL_DIR/reducer.jq") ||
    ! jq -e --argjson report "$WRITE_REPORT_NONE" '
      .provenance["docs/r.mdx"].writeStatus == "written" and
      .provenance["docs/r.mdx"].writerReport == $report
    ' <<<"$WRITTEN_NONE" >/dev/null; then
    contract_failure 'Healthy GAPS:none writer report was not persisted atomically'
  fi
  if ! COMPLETED_AFTER_WRITE=$(jq -n -L "$CONTROL_DIR" --argjson state "$WRITTEN_NONE" \
    --arg operation complete-tier --argjson data '{}' -f "$CONTROL_DIR/reducer.jq") ||
    [[ $(jq -r '.step' <<<"$COMPLETED_AFTER_WRITE") != completed ]]; then
    contract_failure 'Healthy record-write did not satisfy the tier-completion report fence'
  fi
  if ! WRITTEN_VALID=$(jq -n -L "$CONTROL_DIR" --argjson state "$PENDING_WRITE_STATE" \
    --arg operation record-write --argjson data "$WRITE_DATA_VALID" -f "$CONTROL_DIR/reducer.jq") ||
    ! jq -e --argjson report "$WRITE_REPORT_VALID" '
      .provenance["docs/r.mdx"].writeStatus == "written" and
      .provenance["docs/r.mdx"].writtenHash == $report.writtenHash and
      .provenance["docs/r.mdx"].writerReport == $report
    ' <<<"$WRITTEN_VALID" >/dev/null; then
    contract_failure 'Healthy structured writer report was not persisted atomically'
  fi

  BLANK_REASON_REPORT=$(jq -c '.gaps[0].reason = "   "' <<<"$WRITE_REPORT_VALID")
  WRONG_TIER_REPORT=$(jq -c '.gaps[0].tier = 3' <<<"$WRITE_REPORT_VALID")
  CONFLICTING_REPORT=$(jq -c '.gaps += [{
    path:"docs/a.mdx",type:"algorithm",tier:3,reason:"Conflicting algorithm claim"
  }]' <<<"$WRITE_REPORT_VALID")
  EXTRA_KEY_REPORT=$(jq -c '.attackerJunk = true' <<<"$WRITE_REPORT_VALID")
  REPORT_CASE_NAMES=(BLANK_REASON_REPORT WRONG_TIER_REPORT CONFLICTING_REPORT EXTRA_KEY_REPORT)
  REPORT_CASE_VALUES=("$BLANK_REASON_REPORT" "$WRONG_TIER_REPORT" "$CONFLICTING_REPORT" "$EXTRA_KEY_REPORT")
  for REPORT_CASE_INDEX in "${!REPORT_CASE_NAMES[@]}"; do
    REPORT_CASE=${REPORT_CASE_NAMES[$REPORT_CASE_INDEX]}
    REPORT=${REPORT_CASE_VALUES[$REPORT_CASE_INDEX]}
    BAD_WRITE_DATA=$(jq -cn --arg hash "$FILE_HASH" --argjson report "$REPORT" '{
      path:"docs/r.mdx",returnedHash:$hash,diskHash:$hash,writerReport:$report
    }')
    printf '%s' "$PENDING_WRITE_STATE" >"$CONTROL_DIR/${REPORT_CASE}.before"
    if OUTPUT=$(jq -n -L "$CONTROL_DIR" --argjson state "$PENDING_WRITE_STATE" \
      --arg operation record-write --argjson data "$BAD_WRITE_DATA" \
      -f "$CONTROL_DIR/reducer.jq" 2>&1); then
      contract_failure "Malformed writer report was accepted: ${REPORT_CASE}"
    elif [[ $OUTPUT != *GAP_REPORT_SET_INVALID* ]]; then
      contract_failure "Malformed writer report failed for the wrong reason: ${REPORT_CASE}"
    fi
    printf '%s' "$PENDING_WRITE_STATE" >"$CONTROL_DIR/${REPORT_CASE}.after"
    if ! cmp -s "$CONTROL_DIR/${REPORT_CASE}.before" "$CONTROL_DIR/${REPORT_CASE}.after"; then
      contract_failure "Malformed writer report mutated state: ${REPORT_CASE}"
    fi
  done
  NULL_REPORT_STATE=$(jq -c '
    .step = "write_tier_4" | .pending = [] |
    .provenance["docs/r.mdx"].writerReport = null
  ' <<<"$BASE_STATE")
  if OUTPUT=$(jq -n -L "$CONTROL_DIR" --argjson state "$NULL_REPORT_STATE" \
    --arg operation complete-tier --argjson data '{}' -f "$CONTROL_DIR/reducer.jq" 2>&1); then
    contract_failure 'Tier completion accepted a missing writer report'
  elif [[ $OUTPUT != *WRITE_REPORT_MISSING* ]]; then
    contract_failure 'Missing writer report failed tier completion for the wrong reason'
  else
    echo '✅ Writer reports persisted atomically and malformed or missing reports were refused'
  fi

  HEALTHY=$(jq -n -L "$CONTROL_DIR" --argjson state "$BASE_STATE" \
    --arg operation prepare-scaffold --argjson data '{}' -f "$CONTROL_DIR/reducer.jq")
  HEALTHY=$(jq -n -L "$CONTROL_DIR" --argjson state "$HEALTHY" \
    --arg operation finalize-scaffold --argjson data '{}' -f "$CONTROL_DIR/reducer.jq")
  if [[ $(jq -r '.step' <<<"$HEALTHY") != write_tier_1 ]]; then
    echo "❌ Healthy initial scaffold did not reach write_tier_1" >&2
    FAILURES=$((FAILURES + 1))
  fi
  GAP_STATE=$(jq -c '.step = "write_tier_4"' <<<"$PLANNED_STATE")
  for TARGET in prepared scaffolded reset cleaned cleared; do
    DATA=$(jq -cn --arg target "$TARGET" '{target:$target}')
    if [[ $TARGET == prepared ]]; then
      DATA='{"target":"prepared","gapPaths":["docs/a.mdx"],"expectedScaffold":{"docs/a.mdx":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}}'
    elif [[ $TARGET == cleaned ]]; then
      DATA='{"target":"cleaned","resetTiers":[2,4],"cleanedTiers":[2,4]}'
    elif [[ $TARGET == cleared ]]; then
      DATA='{"target":"cleared","closedAt":"2026-08-01T00:00:01Z"}'
      PRE_CLEAR_RECORD=$(jq -c '.gapRecord' <<<"$GAP_STATE")
    fi
    GAP_STATE=$(jq -n -L "$CONTROL_DIR" --argjson state "$GAP_STATE" \
      --arg operation gap-advance --argjson data "$DATA" -f "$CONTROL_DIR/reducer.jq")
    if [[ $TARGET == reset ]] && ! jq -e --arg hash "$FILE_HASH" '
      .provenance["docs/r.mdx"].writeStatus == "pending" and
      .provenance["docs/r.mdx"].writerReport == null and
      .provenance["docs/r.mdx"].writtenHash == $hash
    ' <<<"$GAP_STATE" >/dev/null; then
      contract_failure 'Gap reset did not requeue the reporter, clear its report, and retain its written hash'
    fi
  done
  if [[ $(jq -r '.gapStatus' <<<"$GAP_STATE") != null ]] ||
    [[ $(jq -r '.gapsResolved | length' <<<"$GAP_STATE") -ne 1 ]] ||
    ! cmp -s \
      <(jq -cS 'del(.status,.closedAt)' <<<"$(jq -c '.gapsResolved[0]' <<<"$GAP_STATE")") \
      <(jq -cS 'del(.status)' <<<"$PRE_CLEAR_RECORD") ||
    ! jq -n -L "$CONTROL_DIR" --argjson state "$GAP_STATE" --arg operation write-dispatch \
      --argjson data '{}' -f "$CONTROL_DIR/reducer.jq" >/dev/null; then
    echo "❌ Healthy gap path did not clear" >&2
    FAILURES=$((FAILURES + 1))
  else
    echo '✅ Healthy gap close preserved the full transition and reset cleared durable reports'
  fi

  # The reducer is intentionally a small executable model, but its names and record
  # shapes are tied back to the marked Markdown sources below.  It proves that every
  # ordinary dispatch/handoff shares the same approved-plan guard and that the only
  # successor is the named gap candidate transaction.
  PLAN_BASE=$(jq -c '.step = "write_tier_1"' <<<"$BASE_STATE")

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
  ROOT_MISMATCH=$(jq -c --arg hash "$PLAN_C" '.planStateHash = $hash' <<<"$PLAN_BASE")
  if OUTPUT=$(jq -n -L "$CONTROL_DIR" --argjson state "$ROOT_MISMATCH" \
    --arg operation write-dispatch --argjson data '{}' -f "$CONTROL_DIR/reducer.jq" 2>&1); then
    contract_failure 'Immutable approved-root mismatch was accepted'
  elif [[ $OUTPUT != *PLAN_DRIFT_BLOCKED* ]]; then
    contract_failure 'Immutable approved-root mismatch failed for the wrong reason'
  fi
  SILENT_REBIND=$(jq -c --arg hash "$PLAN_C" \
    '.authorizedPlanHash = $hash | .livePlanHash = $hash' <<<"$PLAN_BASE")
  if OUTPUT=$(jq -n -L "$CONTROL_DIR" --argjson state "$SILENT_REBIND" \
    --arg operation audit-dispatch --argjson data '{}' -f "$CONTROL_DIR/reducer.jq" 2>&1); then
    contract_failure 'Authorized/live hashes silently rebound away from the approved root'
  elif [[ $OUTPUT != *PLAN_DRIFT_BLOCKED* ]]; then
    contract_failure 'Silent authority rebind failed for the wrong reason'
  fi
  VALID_CLOSED_CHAIN=$(jq -c --arg hash "$PLAN_C" --argjson first "$CLOSED_RECORD_AB" \
    --argjson second "$CLOSED_RECORD_BC" --arg scaffoldA "$SCAFFOLD_A" \
    --arg scaffoldB "$SCAFFOLD_B" '
      .gapsResolved = [$first,$second] |
      .authorizedPlanHash = $hash | .livePlanHash = $hash |
      .writeQueue += ["docs/a.mdx","docs/b.mdx"] |
      .provenance["docs/a.mdx"] = {
        tier:2,writeStatus:"pending",scaffoldHash:$scaffoldA,
        writtenHash:null,writerReport:null
      } |
      .provenance["docs/b.mdx"] = {
        tier:3,writeStatus:"pending",scaffoldHash:$scaffoldB,
        writtenHash:null,writerReport:null
      }
    ' <<<"$PLAN_BASE")
  if ! jq -n -L "$CONTROL_DIR" --argjson state "$VALID_CLOSED_CHAIN" \
    --arg operation write-dispatch --argjson data '{}' -f "$CONTROL_DIR/reducer.jq" >/dev/null; then
    contract_failure 'Valid two-link closed plan-mutation chain was rejected'
  fi
  REORDERED_CLOSED_CHAIN=$(jq -c '.gapsResolved |= reverse' <<<"$VALID_CLOSED_CHAIN")
  if OUTPUT=$(jq -n -L "$CONTROL_DIR" --argjson state "$REORDERED_CLOSED_CHAIN" \
    --arg operation write-dispatch --argjson data '{}' -f "$CONTROL_DIR/reducer.jq" 2>&1); then
    contract_failure 'Reordered two-link closed chain was accepted'
  elif [[ $OUTPUT != *PLAN_DRIFT_BLOCKED* ]]; then
    contract_failure 'Reordered two-link closed chain failed for the wrong reason'
  fi
  SKIPPED_CLOSED_CHAIN=$(jq -c '.gapsResolved = [.gapsResolved[0]]' <<<"$VALID_CLOSED_CHAIN")
  if OUTPUT=$(jq -n -L "$CONTROL_DIR" --argjson state "$SKIPPED_CLOSED_CHAIN" \
    --arg operation write-dispatch --argjson data '{}' -f "$CONTROL_DIR/reducer.jq" 2>&1); then
    contract_failure 'Skipped-link closed chain was accepted'
  elif [[ $OUTPUT != *PLAN_DRIFT_BLOCKED* ]]; then
    contract_failure 'Skipped-link closed chain failed for the wrong reason'
  fi
  BROKEN_CLOSED_CHAIN=$(jq -c --arg hash "$PLAN_A" \
    '.gapsResolved[1].planMutation.fromPlanHash = $hash' <<<"$VALID_CLOSED_CHAIN")
  if OUTPUT=$(jq -n -L "$CONTROL_DIR" --argjson state "$BROKEN_CLOSED_CHAIN" \
    --arg operation write-dispatch --argjson data '{}' -f "$CONTROL_DIR/reducer.jq" 2>&1); then
    contract_failure 'Broken complete closed chain was accepted'
  elif [[ $OUTPUT != *PLAN_DRIFT_BLOCKED* ]]; then
    contract_failure 'Broken complete closed chain failed for the wrong reason'
  fi

  TRUNCATED_HISTORY=$(jq -c '
    .gapsResolved[0] = {status:"cleared",planMutation:.gapsResolved[0].planMutation}
  ' <<<"$VALID_CLOSED_CHAIN")
  NO_REPORT_HISTORY=$(jq -c 'del(.gapsResolved[0].reports)' <<<"$VALID_CLOSED_CHAIN")
  BLANK_REASON_HISTORY=$(jq -c '.gapsResolved[0].reports[0].gaps[0].reason = "   "' \
    <<<"$VALID_CLOSED_CHAIN")
  CONFLICTING_HISTORY=$(jq -c '
    .gapsResolved[0].reports += [{reportedBy:"docs/s.mdx",gaps:[{
      path:"docs/a.mdx",type:"algorithm",tier:3,reason:"Conflicting reporter metadata"
    }]}] |
    .gapsResolved[0].gapPaths += [{path:"docs/a.mdx",type:"algorithm",tier:3}]
  ' <<<"$VALID_CLOSED_CHAIN")
  DUPLICATE_OPENED_HISTORY=$(jq -c '
    .gapsResolved[1].openedAt = .gapsResolved[0].openedAt
  ' <<<"$VALID_CLOSED_CHAIN")
  NO_CLOSED_AT_HISTORY=$(jq -c 'del(.gapsResolved[0].closedAt)' <<<"$VALID_CLOSED_CHAIN")
  DUPLICATE_REPORTER_HISTORY=$(jq -c '
    .gapsResolved[0].reports += [.gapsResolved[0].reports[0]]
  ' <<<"$VALID_CLOSED_CHAIN")
  EMPTY_REQUEUED_HISTORY=$(jq -c '.gapsResolved[0].requeued = []' <<<"$VALID_CLOSED_CHAIN")
  EMPTY_RESET_HISTORY=$(jq -c '
    .gapsResolved[0].resetTiers = [] | .gapsResolved[0].cleanedTiers = []
  ' <<<"$VALID_CLOSED_CHAIN")
  RESET_WITHOUT_REPLAY_HISTORY=$(jq -c '
    .gapsResolved[0].resetTiers = [4] | .gapsResolved[0].cleanedTiers = [4]
  ' <<<"$VALID_CLOSED_CHAIN")
  WRONG_ADDED_ENTRY_HISTORY=$(jq -c '
    .gapsResolved[0].planMutation.addedPlanEntries[0].outputPath = "docs/forged.mdx"
  ' <<<"$VALID_CLOSED_CHAIN")
  MISSING_ADDED_LINK_HISTORY=$(jq -c '
    .gapsResolved[0].planMutation.addedCrossLinks = []
  ' <<<"$VALID_CLOSED_CHAIN")
  HISTORY_CASE_NAMES=(TRUNCATED_HISTORY NO_REPORT_HISTORY BLANK_REASON_HISTORY
    CONFLICTING_HISTORY DUPLICATE_OPENED_HISTORY NO_CLOSED_AT_HISTORY
    DUPLICATE_REPORTER_HISTORY EMPTY_REQUEUED_HISTORY EMPTY_RESET_HISTORY
    RESET_WITHOUT_REPLAY_HISTORY WRONG_ADDED_ENTRY_HISTORY MISSING_ADDED_LINK_HISTORY)
  HISTORY_CASE_VALUES=("$TRUNCATED_HISTORY" "$NO_REPORT_HISTORY" "$BLANK_REASON_HISTORY"
    "$CONFLICTING_HISTORY" "$DUPLICATE_OPENED_HISTORY" "$NO_CLOSED_AT_HISTORY"
    "$DUPLICATE_REPORTER_HISTORY" "$EMPTY_REQUEUED_HISTORY" "$EMPTY_RESET_HISTORY"
    "$RESET_WITHOUT_REPLAY_HISTORY" "$WRONG_ADDED_ENTRY_HISTORY" "$MISSING_ADDED_LINK_HISTORY")
  for HISTORY_CASE_INDEX in "${!HISTORY_CASE_NAMES[@]}"; do
    HISTORY_CASE=${HISTORY_CASE_NAMES[$HISTORY_CASE_INDEX]}
    HISTORY=${HISTORY_CASE_VALUES[$HISTORY_CASE_INDEX]}
    if OUTPUT=$(jq -n -L "$CONTROL_DIR" --argjson state "$HISTORY" \
      --arg operation write-dispatch --argjson data '{}' -f "$CONTROL_DIR/reducer.jq" 2>&1); then
      contract_failure "Malformed closed history was accepted: ${HISTORY_CASE}"
    elif [[ $OUTPUT != *GAP_CLOSURE_INVALID* ]]; then
      contract_failure "Malformed closed history failed for the wrong reason: ${HISTORY_CASE}"
    fi
  done
  if [[ $FAILURES -eq $CONTROL_FAILURES_BEFORE ]]; then
    echo '✅ Complete ordered two-link history rejected reordering, skipped links, and malformed closures'
  fi

  CONTROL_FAILURES_BEFORE=$FAILURES
  BAD_CANDIDATE_STATE=$(jq -c --arg hash "$PLAN_B" '
    .candidateHash = $hash |
    .canonicalCandidatePath = ".contributor-docs/not-the-authorized-candidate.yaml"
  ' <<<"$PLAN_BASE")
  if OUTPUT=$(jq -n -L "$CONTROL_DIR" --argjson state "$BAD_CANDIDATE_STATE" \
    --arg operation authorize-gap-plan --argjson data "$PLAN_INPUT" \
    -f "$CONTROL_DIR/reducer.jq" 2>&1); then
    contract_failure 'Non-canonical gap candidate path was accepted'
  elif [[ $OUTPUT != *GAP_PLAN_DELTA_INVALID* ]]; then
    contract_failure 'Non-canonical gap candidate path failed for the wrong reason'
  fi

  SECOND_FILE_HASH=cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc
  CONFLICTING_LEDGER=$(jq -c --arg hash "$PLAN_B" --arg plan "$PLAN_A" \
    --arg from "$FROM_HASH" --arg written "$SECOND_FILE_HASH" '
      .candidateHash = $hash |
      .writeQueue += ["docs/s.mdx"] |
      .provenance["docs/s.mdx"] = {
        tier:4,writeStatus:"written",scaffoldHash:$from,writtenHash:$written,
        writerReport:{reportedBy:"docs/s.mdx",authorizedPlanHash:$plan,
          authorizedFromHash:$from,writtenHash:$written,gaps:[{
            path:"docs/a.mdx",type:"algorithm",tier:3,reason:"Conflicting reporter metadata"
          }]}
      }
    ' <<<"$PLAN_BASE")
  if OUTPUT=$(jq -n -L "$CONTROL_DIR" --argjson state "$CONFLICTING_LEDGER" \
    --arg operation authorize-gap-plan --argjson data "$PLAN_INPUT" \
    -f "$CONTROL_DIR/reducer.jq" 2>&1); then
    contract_failure 'Conflicting two-reporter ledger was accepted'
  elif [[ $OUTPUT != *GAP_REPORT_SET_INVALID* ]]; then
    contract_failure 'Conflicting two-reporter ledger failed for the wrong reason'
  fi
  CALLER_REPORT_INPUT=$(jq -c '.reports = []' <<<"$PLAN_INPUT")
  if OUTPUT=$(jq -n -L "$CONTROL_DIR" --argjson state \
    "$(jq -c --arg hash "$PLAN_B" '.candidateHash = $hash' <<<"$PLAN_BASE")" \
    --arg operation authorize-gap-plan --argjson data "$CALLER_REPORT_INPUT" \
    -f "$CONTROL_DIR/reducer.jq" 2>&1); then
    contract_failure 'Caller-supplied reports bypassed the durable ledger'
  elif [[ $OUTPUT != *GAP_REPORT_SET_INVALID* ]]; then
    contract_failure 'Caller-supplied reports failed for the wrong reason'
  fi
  EXTRA_KEY_PLAN_INPUT=$(jq -c '.attackerJunk = true' <<<"$PLAN_INPUT")
  if OUTPUT=$(jq -n -L "$CONTROL_DIR" --argjson state \
    "$(jq -c --arg hash "$PLAN_B" '.candidateHash = $hash' <<<"$PLAN_BASE")" \
    --arg operation authorize-gap-plan --argjson data "$EXTRA_KEY_PLAN_INPUT" \
    -f "$CONTROL_DIR/reducer.jq" 2>&1); then
    contract_failure 'Gap authorization accepted an unknown input field'
  elif [[ $OUTPUT != *GAP_PLAN_DELTA_INVALID* ]]; then
    contract_failure 'Unknown gap-authorization field failed for the wrong reason'
  fi
  if [[ $FAILURES -eq $CONTROL_FAILURES_BEFORE ]]; then
    echo '✅ Candidate path and durable two-reporter ledger authority were enforced'
  fi

  CONTROL_FAILURES_BEFORE=$FAILURES
  AUTHORIZABLE_STATE=$(jq -c --arg hash "$PLAN_B" '.candidateHash = $hash' <<<"$PLAN_BASE")
  if ! AUTHORIZED=$(jq -n -L "$CONTROL_DIR" --argjson state "$AUTHORIZABLE_STATE" \
    --arg operation authorize-gap-plan --argjson data "$PLAN_INPUT" -f "$CONTROL_DIR/reducer.jq"); then
    contract_failure 'Valid authorize-gap-plan was refused'
  elif [[ $(jq -r '.gapStatus' <<<"$AUTHORIZED") != enqueued ]] ||
    [[ $(jq -r '.authorizedPlanHash' <<<"$AUTHORIZED") != "$PLAN_A" ]] ||
    ! jq -e --argjson report "$WRITE_REPORT_VALID" '
      .gapRecord.reports == [{reportedBy:$report.reportedBy,gaps:$report.gaps}]
    ' <<<"$AUTHORIZED" >/dev/null; then
    contract_failure 'authorize-gap-plan changed authority or did not derive reports from provenance'
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
    UNRELATED_STATE=$(jq -c --arg hash "$UNRELATED_HASH" '.candidateHash = $hash' <<<"$PLAN_BASE")
    printf '%s' "$UNRELATED_STATE" >"$CONTROL_DIR/unrelated-plan.before"
    if OUTPUT=$(jq -n -L "$CONTROL_DIR" --argjson state "$UNRELATED_STATE" \
      --arg operation authorize-gap-plan --argjson data "$UNRELATED_INPUT" \
      -f "$CONTROL_DIR/reducer.jq" 2>&1); then
      contract_failure 'Candidate-byte mutation with an unrelated source was accepted'
    elif [[ $OUTPUT != *GAP_PLAN_DELTA_INVALID* ]]; then
      contract_failure 'Candidate-byte mutation failed for the wrong reason'
    fi
    printf '%s' "$UNRELATED_STATE" >"$CONTROL_DIR/unrelated-plan.after"
    if ! cmp -s "$CONTROL_DIR/unrelated-plan.before" "$CONTROL_DIR/unrelated-plan.after"; then
      contract_failure 'Rejected candidate-byte mutation changed authority state'
    fi
    if [[ $FAILURES -eq $CONTROL_FAILURES_BEFORE ]]; then
      echo '✅ Extra semantic candidate-byte delta was rejected without changing authority'
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

  CONTROL_FAILURES_BEFORE=$FAILURES
  AFTER_ONE_CLOSED=$(jq -c --arg hash "$PLAN_B" --argjson closed "$CLOSED_RECORD_AB" \
    --arg scaffold "$SCAFFOLD_A" '
    .gapsResolved = [$closed] | .authorizedPlanHash = $hash | .livePlanHash = $hash |
    .writeQueue += ["docs/a.mdx"] |
    .provenance["docs/a.mdx"] = {
      tier:2,writeStatus:"pending",scaffoldHash:$scaffold,
      writtenHash:null,writerReport:null
    } |
    .provenance["docs/r.mdx"].writerReport.authorizedPlanHash = $hash |
    .provenance["docs/r.mdx"].writerReport.gaps = [{
      path:"docs/b.mdx",type:"algorithm",tier:3,reason:"Reporter needs the algorithm"
    }]
  ' <<<"$PLAN_BASE")
  AFTER_ONE_CLOSED=$(jq -c --arg hash "$PLAN_C" '.candidateHash = $hash' <<<"$AFTER_ONE_CLOSED")
  if ! SECOND_AUTHORIZED=$(jq -n -L "$CONTROL_DIR" --argjson state "$AFTER_ONE_CLOSED" \
    --arg operation authorize-gap-plan --argjson data "$SECOND_PLAN_INPUT" -f "$CONTROL_DIR/reducer.jq") ||
    ! SECOND_APPLIED=$(jq -n -L "$CONTROL_DIR" --argjson state "$SECOND_AUTHORIZED" \
      --arg operation apply-gap-plan --argjson data '{}' -f "$CONTROL_DIR/reducer.jq") ||
    ! jq -n -L "$CONTROL_DIR" --argjson state "$SECOND_APPLIED" \
      --arg operation write-dispatch --argjson data '{}' -f "$CONTROL_DIR/reducer.jq" >/dev/null; then
    contract_failure 'A second exact successor after a closed mutation was refused'
  fi
  if [[ $FAILURES -eq $CONTROL_FAILURES_BEFORE ]]; then
    echo '✅ A second exact successor was accepted after the first closed mutation'
  fi

  # Exercise the real authority helper and both processor scripts against an isolated
  # temporary git repository. These controls prove the production predicates and atomic
  # rename fences, rather than only the executable reducer model above.
  CONTROL_FAILURES_BEFORE=$FAILURES
  AUTHORITY_DIR="$CONTROL_DIR/authority"
  mkdir -p "$AUTHORITY_DIR"
  AUTH_PLAN_STATE=$(jq -cn --arg hash "$PLAN_A" '{
    step:"completed",diffSummaryReady:true,
    diffSummaryHash:"ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
    planFile:".contributor-docs/doc-plan.yaml",planHash:$hash,
    reviewFeedback:null,approved:true
  }')
  AUTH_WRITE_STATE=$(jq -cn --arg hash "$PLAN_A" --arg scaffold "$FROM_HASH" \
    --arg written "$FILE_HASH" --argjson report "$WRITE_REPORT_VALID" '{
      step:"write_tier_4",authorizedPlanHash:$hash,scaffoldComplete:true,currentTier:4,
      tiersCompleted:[1,2,3],filesWritten:1,filesTotal:1,writeQueue:["docs/r.mdx"],
      provenance:{"docs/r.mdx":{
        origin:"new",scaffoldHash:$scaffold,scaffoldedAt:"2026-08-01T00:00:00Z",
        tier:4,writeStatus:"written",writtenHash:$written,writerReport:$report
      }},approvedOverwrites:[],blockedCollisions:[],auditRepair:null,
      gapTransition:null,gapsResolved:[]
    }')
  AUTH_PLAN_FILE="$AUTHORITY_DIR/doc-plan.yaml"
  AUTH_PLAN_STATE_FILE="$AUTHORITY_DIR/plan-state.json"
  AUTH_WRITE_STATE_FILE="$AUTHORITY_DIR/write-state.json"
  AUTH_CANDIDATE_FILE="$AUTHORITY_DIR/doc-plan.gap-candidate.yaml"
  printf '%s\n' "$AUTH_PLAN_STATE" >"$AUTH_PLAN_STATE_FILE"
  printf '%s\n' "$AUTH_WRITE_STATE" >"$AUTH_WRITE_STATE_FILE"
  printf '%s' "$LIVE_PLAN_BYTES" >"$AUTH_PLAN_FILE"
  if ! assert_plan_authority "$PLAN_A" "$AUTH_PLAN_STATE_FILE" "$AUTH_WRITE_STATE_FILE" \
    "$AUTH_PLAN_FILE" "$AUTH_CANDIDATE_FILE"; then
    contract_failure 'Healthy direct authority helper call was refused'
  fi

  GUTTED_WRITE_STATE=$(jq -cn --arg hash "$PLAN_A" '{
    authorizedPlanHash:$hash,gapTransition:null,gapsResolved:[],
    attackerJunk:"anything",step:"NOT_A_REAL_STEP"
  }')
  printf '%s\n' "$GUTTED_WRITE_STATE" >"$AUTH_WRITE_STATE_FILE"
  cp "$AUTH_WRITE_STATE_FILE" "$CONTROL_DIR/helper-gutted.before"
  if OUTPUT=$(assert_plan_authority "$PLAN_A" "$AUTH_PLAN_STATE_FILE" \
    "$AUTH_WRITE_STATE_FILE" "$AUTH_PLAN_FILE" "$AUTH_CANDIDATE_FILE" 2>&1); then
    contract_failure 'Direct authority helper accepted a gutted write-state object'
  elif [[ $OUTPUT != *PLAN_DRIFT_BLOCKED* ]]; then
    contract_failure 'Direct authority helper reported a gutted write state with the wrong refusal'
  elif ! cmp -s "$AUTH_WRITE_STATE_FILE" "$CONTROL_DIR/helper-gutted.before"; then
    contract_failure 'Direct authority helper mutated the gutted write state while refusing it'
  fi
  printf '%s\n' "$AUTH_WRITE_STATE" >"$AUTH_WRITE_STATE_FILE"

  printf '%s' "$UNRELATED_PLAN_BYTES" >"$AUTH_PLAN_FILE"
  cp "$AUTH_PLAN_STATE_FILE" "$CONTROL_DIR/helper-tamper-plan.before"
  cp "$AUTH_WRITE_STATE_FILE" "$CONTROL_DIR/helper-tamper-write.before"
  if OUTPUT=$(assert_plan_authority "$PLAN_A" "$AUTH_PLAN_STATE_FILE" \
    "$AUTH_WRITE_STATE_FILE" "$AUTH_PLAN_FILE" "$AUTH_CANDIDATE_FILE" 2>&1); then
    contract_failure 'Direct authority helper accepted live-plan byte tampering'
  elif [[ $OUTPUT != *PLAN_DRIFT_BLOCKED* ]]; then
    contract_failure 'Direct authority helper reported live-plan tampering with the wrong refusal'
  elif ! cmp -s "$AUTH_PLAN_STATE_FILE" "$CONTROL_DIR/helper-tamper-plan.before" ||
    ! cmp -s "$AUTH_WRITE_STATE_FILE" "$CONTROL_DIR/helper-tamper-write.before"; then
    contract_failure 'Direct authority helper mutated state while refusing live-plan tampering'
  fi

  printf '%s' "$LIVE_PLAN_BYTES" >"$AUTH_PLAN_FILE"
  printf '%s' "$CANDIDATE_PLAN_BYTES" >"$AUTH_CANDIDATE_FILE"
  cp "$AUTH_PLAN_STATE_FILE" "$CONTROL_DIR/helper-candidate-plan.before"
  cp "$AUTH_WRITE_STATE_FILE" "$CONTROL_DIR/helper-candidate-write.before"
  if OUTPUT=$(assert_plan_authority "$PLAN_A" "$AUTH_PLAN_STATE_FILE" \
    "$AUTH_WRITE_STATE_FILE" "$AUTH_PLAN_FILE" "$AUTH_CANDIDATE_FILE" 2>&1); then
    contract_failure 'Direct authority helper accepted a present candidate sidecar'
  elif [[ $OUTPUT != *PLAN_DRIFT_BLOCKED* ]]; then
    contract_failure 'Direct authority helper reported candidate presence with the wrong refusal'
  elif ! cmp -s "$AUTH_PLAN_STATE_FILE" "$CONTROL_DIR/helper-candidate-plan.before" ||
    ! cmp -s "$AUTH_WRITE_STATE_FILE" "$CONTROL_DIR/helper-candidate-write.before"; then
    contract_failure 'Direct authority helper mutated state while refusing candidate presence'
  fi
  rm -f "$AUTH_CANDIDATE_FILE"

  CHAIN_WRITE_STATE=$(jq -c --arg hash "$PLAN_C" --argjson first "$CLOSED_RECORD_AB" \
    --argjson second "$CLOSED_RECORD_BC" --arg scaffoldA "$SCAFFOLD_A" \
    --arg scaffoldB "$SCAFFOLD_B" '
      .authorizedPlanHash = $hash | .gapsResolved = [$first,$second] |
      .writeQueue += ["docs/a.mdx","docs/b.mdx"] | .filesTotal = 3 | .filesWritten = 0 |
      .provenance["docs/r.mdx"].writeStatus = "pending" |
      .provenance["docs/r.mdx"].writerReport = null |
      .provenance["docs/a.mdx"] = {
        origin:"new",scaffoldHash:$scaffoldA,scaffoldedAt:"2026-08-01T00:00:00Z",
        tier:2,writeStatus:"pending",writtenHash:null,writerReport:null
      } |
      .provenance["docs/b.mdx"] = {
        origin:"new",scaffoldHash:$scaffoldB,scaffoldedAt:"2026-08-01T00:01:00Z",
        tier:3,writeStatus:"pending",writtenHash:null,writerReport:null
      }
    ' <<<"$AUTH_WRITE_STATE")
  printf '%s\n' "$CHAIN_WRITE_STATE" >"$AUTH_WRITE_STATE_FILE"
  printf '%s' "$SECOND_PLAN_BYTES" >"$AUTH_PLAN_FILE"
  if ! assert_plan_authority "$PLAN_C" "$AUTH_PLAN_STATE_FILE" "$AUTH_WRITE_STATE_FILE" \
    "$AUTH_PLAN_FILE" "$AUTH_CANDIDATE_FILE"; then
    contract_failure 'Direct authority helper rejected a healthy complete two-link chain'
  fi
  HELPER_TRUNCATED=$(jq -c 'del(.gapsResolved[0].reports)' <<<"$CHAIN_WRITE_STATE")
  HELPER_DUPLICATE_REPORTER=$(jq -c '
    .gapsResolved[0].reports += [.gapsResolved[0].reports[0]]
  ' <<<"$CHAIN_WRITE_STATE")
  HELPER_EMPTY_REQUEUED=$(jq -c '.gapsResolved[0].requeued = []' <<<"$CHAIN_WRITE_STATE")
  HELPER_EMPTY_RESET=$(jq -c '
    .gapsResolved[0].resetTiers = [] | .gapsResolved[0].cleanedTiers = []
  ' <<<"$CHAIN_WRITE_STATE")
  HELPER_RESET_WITHOUT_REPLAY=$(jq -c '
    .gapsResolved[0].resetTiers = [4] | .gapsResolved[0].cleanedTiers = [4]
  ' <<<"$CHAIN_WRITE_STATE")
  HELPER_WRONG_ADDED_ENTRY=$(jq -c '
    .gapsResolved[0].planMutation.addedPlanEntries[0].outputPath = "docs/forged.mdx"
  ' <<<"$CHAIN_WRITE_STATE")
  HELPER_WRONG_ADDED_DESCRIPTION=$(jq -c '
    .gapsResolved[0].planMutation.addedPlanEntries[0].entry.description = "forged history"
  ' <<<"$CHAIN_WRITE_STATE")
  HELPER_MISSING_ADDED_LINK=$(jq -c '
    .gapsResolved[0].planMutation.addedCrossLinks = []
  ' <<<"$CHAIN_WRITE_STATE")
  HELPER_CASE_NAMES=(HELPER_TRUNCATED HELPER_DUPLICATE_REPORTER HELPER_EMPTY_REQUEUED
    HELPER_EMPTY_RESET HELPER_RESET_WITHOUT_REPLAY HELPER_WRONG_ADDED_ENTRY
    HELPER_WRONG_ADDED_DESCRIPTION HELPER_MISSING_ADDED_LINK)
  HELPER_CASE_VALUES=("$HELPER_TRUNCATED" "$HELPER_DUPLICATE_REPORTER" "$HELPER_EMPTY_REQUEUED"
    "$HELPER_EMPTY_RESET" "$HELPER_RESET_WITHOUT_REPLAY" "$HELPER_WRONG_ADDED_ENTRY"
    "$HELPER_WRONG_ADDED_DESCRIPTION" "$HELPER_MISSING_ADDED_LINK")
  for HELPER_CASE_INDEX in "${!HELPER_CASE_NAMES[@]}"; do
    HELPER_CASE=${HELPER_CASE_NAMES[$HELPER_CASE_INDEX]}
    HELPER_HISTORY=${HELPER_CASE_VALUES[$HELPER_CASE_INDEX]}
    printf '%s\n' "$HELPER_HISTORY" >"$AUTH_WRITE_STATE_FILE"
    cp "$AUTH_WRITE_STATE_FILE" "$CONTROL_DIR/${HELPER_CASE}.before"
    if OUTPUT=$(assert_plan_authority "$PLAN_C" "$AUTH_PLAN_STATE_FILE" \
      "$AUTH_WRITE_STATE_FILE" "$AUTH_PLAN_FILE" "$AUTH_CANDIDATE_FILE" 2>&1); then
      contract_failure "Direct authority helper accepted malformed history: ${HELPER_CASE}"
    elif [[ $OUTPUT != *GAP_CLOSURE_INVALID* ]]; then
      contract_failure "Direct authority helper reported malformed history with the wrong refusal: ${HELPER_CASE}"
    elif ! cmp -s "$AUTH_WRITE_STATE_FILE" "$CONTROL_DIR/${HELPER_CASE}.before"; then
      contract_failure "Direct authority helper mutated malformed history while refusing: ${HELPER_CASE}"
    fi
  done
  if [[ $FAILURES -eq $CONTROL_FAILURES_BEFORE ]]; then
    echo '✅ Direct authority helper enforced live bytes, candidate absence, and complete chain identity'
  fi

  CONTROL_FAILURES_BEFORE=$FAILURES
  PROCESSOR_REPO="$CONTROL_DIR/processor-repo"
  git init -q "$PROCESSOR_REPO"
  mkdir -p "$PROCESSOR_REPO/.contributor-docs" "$PROCESSOR_REPO/docs"
  PROCESSOR_PLAN_STATE="$PROCESSOR_REPO/.contributor-docs/plan-state.json"
  PROCESSOR_WRITE_STATE="$PROCESSOR_REPO/.contributor-docs/write-state.json"
  PROCESSOR_PLAN="$PROCESSOR_REPO/.contributor-docs/doc-plan.yaml"
  PROCESSOR_STATE="$PROCESSOR_REPO/.contributor-docs/write-tier-4/state.json"
  PROCESSOR_PENDING_WRITE=$(jq -c '
    .filesWritten = 0 |
    .provenance["docs/r.mdx"].writeStatus = "pending" |
    .provenance["docs/r.mdx"].writtenHash = null |
    .provenance["docs/r.mdx"].writerReport = null
  ' <<<"$AUTH_WRITE_STATE")
  printf '%s\n' "$AUTH_PLAN_STATE" >"$PROCESSOR_PLAN_STATE"
  printf '%s\n' "$PROCESSOR_PENDING_WRITE" >"$PROCESSOR_WRITE_STATE"
  printf '%s' "$LIVE_PLAN_BYTES" >"$PROCESSOR_PLAN"
  printf '%s' "$FILE_BYTES" >"$PROCESSOR_REPO/docs/r.mdx"
  if ! printf '%s\n' 'docs/r.mdx' | (
    cd "$PROCESSOR_REPO" && bash "$CD_ROOT/scripts/init-state.sh" \
      .contributor-docs/write-tier-4/state.json '["src/r.ts"]' 1 out \
      --plan-hash "$PLAN_A"
  ) >/dev/null; then
    contract_failure 'Healthy processor initialization was refused'
  elif ! jq -e --arg hash "$PLAN_A" '
    .authorizedPlanHash == $hash and .pendingFiles == ["docs/r.mdx"]
  ' "$PROCESSOR_STATE" >/dev/null; then
    contract_failure 'Processor initialization did not persist its authority token and queue'
  fi

  INIT_COLLISION_WRITE=$(jq -c '.blockedCollisions = [{path:"docs/r.mdx"}]' \
    <<<"$PROCESSOR_PENDING_WRITE")
  printf '%s\n' "$INIT_COLLISION_WRITE" >"$PROCESSOR_WRITE_STATE"
  cp "$PROCESSOR_STATE" "$CONTROL_DIR/init-collision.before"
  if OUTPUT=$(printf '%s\n' 'docs/r.mdx' | (
    cd "$PROCESSOR_REPO" && bash "$CD_ROOT/scripts/init-state.sh" \
      .contributor-docs/write-tier-4/state.json '["src/r.ts"]' 1 out \
      --plan-hash "$PLAN_A"
  ) 2>&1); then
    contract_failure 'Processor initialization accepted a collision recorded after authorization'
  elif [[ $OUTPUT != *PROCESSOR_AUTHORITY_INVALID* ]]; then
    contract_failure 'Processor initialization reported a collision race with the wrong refusal'
  elif ! cmp -s "$PROCESSOR_STATE" "$CONTROL_DIR/init-collision.before"; then
    contract_failure 'Processor initialization changed state while refusing a collision race'
  fi

  printf '%s\n' "$PROCESSOR_PENDING_WRITE" >"$PROCESSOR_WRITE_STATE"
  cp "$PROCESSOR_STATE" "$CONTROL_DIR/init-slice.before"
  if OUTPUT=$(printf '%s\n' 'docs/not-authorized.mdx' | (
    cd "$PROCESSOR_REPO" && bash "$CD_ROOT/scripts/init-state.sh" \
      .contributor-docs/write-tier-4/state.json '["src/r.ts"]' 1 out \
      --plan-hash "$PLAN_A"
  ) 2>&1); then
    contract_failure 'Processor initialization accepted a caller-substituted tier slice'
  elif [[ $OUTPUT != *PROCESSOR_AUTHORITY_INVALID* ]]; then
    contract_failure 'Processor initialization reported a stale slice with the wrong refusal'
  elif ! cmp -s "$PROCESSOR_STATE" "$CONTROL_DIR/init-slice.before"; then
    contract_failure 'Processor initialization changed state while refusing a stale slice'
  fi

  printf '%s\n' "$PROCESSOR_PENDING_WRITE" >"$PROCESSOR_WRITE_STATE"
  cp "$PROCESSOR_STATE" "$CONTROL_DIR/init-drift.before"
  printf '%s' "$UNRELATED_PLAN_BYTES" >"$PROCESSOR_PLAN"
  if OUTPUT=$(printf '%s\n' 'docs/r.mdx' | (
    cd "$PROCESSOR_REPO" && bash "$CD_ROOT/scripts/init-state.sh" \
      .contributor-docs/write-tier-4/state.json '["src/r.ts"]' 1 out \
      --plan-hash "$PLAN_A"
  ) 2>&1); then
    contract_failure 'Processor initialization accepted live-plan drift'
  elif [[ $OUTPUT != *PLAN_DRIFT_BLOCKED* ]]; then
    contract_failure 'Processor initialization reported live-plan drift with the wrong refusal'
  elif ! cmp -s "$PROCESSOR_STATE" "$CONTROL_DIR/init-drift.before"; then
    contract_failure 'Processor initialization changed its state while refusing plan drift'
  fi

  printf '%s' "$LIVE_PLAN_BYTES" >"$PROCESSOR_PLAN"
  printf '%s\n' "$AUTH_WRITE_STATE" >"$PROCESSOR_WRITE_STATE"
  cp "$PROCESSOR_STATE" "$CONTROL_DIR/mark-drift.before"
  printf '%s' "$UNRELATED_PLAN_BYTES" >"$PROCESSOR_PLAN"
  if OUTPUT=$(
    cd "$PROCESSOR_REPO" && bash "$CD_ROOT/scripts/mark-done.sh" \
      .contributor-docs/write-tier-4/state.json docs/r.mdx --plan-hash "$PLAN_A" 2>&1
  ); then
    contract_failure 'Processor completion accepted plan drift'
  elif [[ $OUTPUT != *PLAN_DRIFT_BLOCKED* ]]; then
    contract_failure 'Processor completion reported plan drift with the wrong refusal'
  elif ! cmp -s "$PROCESSOR_STATE" "$CONTROL_DIR/mark-drift.before"; then
    contract_failure 'Processor completion changed state while refusing plan drift'
  fi

  printf '%s' "$LIVE_PLAN_BYTES" >"$PROCESSOR_PLAN"
  MARK_COLLISION_WRITE=$(jq -c '.blockedCollisions = [{path:"docs/r.mdx"}]' \
    <<<"$AUTH_WRITE_STATE")
  printf '%s\n' "$MARK_COLLISION_WRITE" >"$PROCESSOR_WRITE_STATE"
  cp "$PROCESSOR_STATE" "$CONTROL_DIR/mark-collision.before"
  if OUTPUT=$(
    cd "$PROCESSOR_REPO" && bash "$CD_ROOT/scripts/mark-done.sh" \
      .contributor-docs/write-tier-4/state.json docs/r.mdx --plan-hash "$PLAN_A" 2>&1
  ); then
    contract_failure 'Processor completion accepted a collision recorded after authorization'
  elif [[ $OUTPUT != *PROCESSOR_AUTHORITY_INVALID* ]]; then
    contract_failure 'Processor completion reported a collision race with the wrong refusal'
  elif ! cmp -s "$PROCESSOR_STATE" "$CONTROL_DIR/mark-collision.before"; then
    contract_failure 'Processor completion changed state while refusing a collision race'
  fi

  printf '%s\n' "$AUTH_WRITE_STATE" >"$PROCESSOR_WRITE_STATE"
  printf '%s' 'tampered writer output' >"$PROCESSOR_REPO/docs/r.mdx"
  cp "$PROCESSOR_STATE" "$CONTROL_DIR/mark-bytes.before"
  if OUTPUT=$(
    cd "$PROCESSOR_REPO" && bash "$CD_ROOT/scripts/mark-done.sh" \
      .contributor-docs/write-tier-4/state.json docs/r.mdx --plan-hash "$PLAN_A" 2>&1
  ); then
    contract_failure 'Processor completion accepted written-byte drift after authorization'
  elif [[ $OUTPUT != *WRITTEN_BYTES_CHANGED* ]]; then
    contract_failure 'Processor completion reported written-byte drift with the wrong refusal'
  elif ! cmp -s "$PROCESSOR_STATE" "$CONTROL_DIR/mark-bytes.before"; then
    contract_failure 'Processor completion changed state while refusing written-byte drift'
  fi
  printf '%s' "$FILE_BYTES" >"$PROCESSOR_REPO/docs/r.mdx"

  NULL_REPORT_WRITE=$(jq -c '.provenance["docs/r.mdx"].writerReport = null' \
    <<<"$AUTH_WRITE_STATE")
  printf '%s\n' "$NULL_REPORT_WRITE" >"$PROCESSOR_WRITE_STATE"
  cp "$PROCESSOR_STATE" "$CONTROL_DIR/mark-report.before"
  if OUTPUT=$(
    cd "$PROCESSOR_REPO" && bash "$CD_ROOT/scripts/mark-done.sh" \
      .contributor-docs/write-tier-4/state.json docs/r.mdx --plan-hash "$PLAN_A" 2>&1
  ); then
    contract_failure 'Processor completion accepted a missing canonical writer report'
  elif [[ $OUTPUT != *GAP_REPORT_SET_INVALID* ]]; then
    contract_failure 'Processor completion reported a missing writer report with the wrong refusal'
  elif ! cmp -s "$PROCESSOR_STATE" "$CONTROL_DIR/mark-report.before"; then
    contract_failure 'Processor completion changed state while refusing a missing report'
  fi

  MALFORMED_PROCESSOR_WRITE=$(jq -c '
    .provenance["docs/r.mdx"].writerReport.attackerJunk = true
  ' <<<"$AUTH_WRITE_STATE")
  printf '%s\n' "$MALFORMED_PROCESSOR_WRITE" >"$PROCESSOR_WRITE_STATE"
  cp "$PROCESSOR_STATE" "$CONTROL_DIR/mark-malformed-report.before"
  if OUTPUT=$(
    cd "$PROCESSOR_REPO" && bash "$CD_ROOT/scripts/mark-done.sh" \
      .contributor-docs/write-tier-4/state.json docs/r.mdx --plan-hash "$PLAN_A" 2>&1
  ); then
    contract_failure 'Processor completion accepted an unknown writer-report field'
  elif [[ $OUTPUT != *GAP_REPORT_SET_INVALID* ]]; then
    contract_failure 'Malformed processor writer report failed with the wrong refusal'
  elif ! cmp -s "$PROCESSOR_STATE" "$CONTROL_DIR/mark-malformed-report.before"; then
    contract_failure 'Processor completion changed state while refusing a malformed report'
  fi

  printf '%s\n' "$AUTH_WRITE_STATE" >"$PROCESSOR_WRITE_STATE"
  if ! (
    cd "$PROCESSOR_REPO" && bash "$CD_ROOT/scripts/mark-done.sh" \
      .contributor-docs/write-tier-4/state.json docs/r.mdx --plan-hash "$PLAN_A"
  ) >/dev/null; then
    contract_failure 'Healthy processor completion was refused'
  elif ! jq -e '
    .pendingFiles == [] and .processedFiles == ["docs/r.mdx"]
  ' "$PROCESSOR_STATE" >/dev/null; then
    contract_failure 'Healthy processor completion did not move the exact queued path atomically'
  fi
  if [[ $FAILURES -eq $CONTROL_FAILURES_BEFORE ]]; then
    echo '✅ Processor fences refused plan, collision, slice, report, and byte drift byte-identically'
  fi

  for LITERAL in authorizedPlanHash authorize-gap-plan apply-gap-plan PLAN_DRIFT_BLOCKED \
    GAP_PLAN_DELTA_INVALID GAP_PLAN_HASH_INVALID GAP_PLAN_CANDIDATE_MISSING \
    GAP_REPORT_SET_INVALID GAP_CLOSURE_INVALID WRITE_REPORT_MISSING \
    PROCESSOR_AUTHORITY_INVALID; do
    if ! rg -qF "$LITERAL" "$WRITE_PHASE" || ! rg -qF "$LITERAL" "$WRITE_AGENT"; then
      contract_failure "Reducer literal is not documented: $LITERAL"
    fi
  done
  echo '✅ Plan-authority reducer controls passed (root chain, full closure, report ledger, successor, refusals, crash adoption)'

  PLAN_REFERENCE_COUNT=$(git -C "$REPO_ROOT" grep -n 'doc-plan.yaml' -- \
    docs/standards/contributor-docs/write | wc -l | tr -d ' ')
  if [[ $PLAN_REFERENCE_COUNT -ne 21 ]]; then
    contract_failure "Plan-metadata reference inventory changed: expected 21, found ${PLAN_REFERENCE_COUNT}"
  fi
  echo "REVIEW_REQUIRED plan-metadata references=$PLAN_REFERENCE_COUNT; confirm each is metadata-only, never queue membership"

  if [[ $FAILURES -ne 0 ]]; then
    echo "❌ Contributor-doc contract controls failed: $FAILURES" >&2
    exit 1
  fi
  echo "✅ Contributor-doc contract controls passed"
  exit 0
fi

[[ $# -eq 6 && $5 == "--plan-hash" ]] || {
  echo "❌ Usage: <file-list> | init-state.sh <state-file> <source-paths-json> <concurrent> <output-dir> --plan-hash <64-hex>" >&2
  exit 1
}

STATE_FILE="$1"
SOURCE_PATHS="$2"
CONCURRENT="$3"
OUTPUT_DIR="$4"
PLAN_HASH="$6"

FILES_JSON=$(jq -R -s 'split("\n") | map(select(. != ""))')
assert_processor_init_authority "$PLAN_HASH" "$STATE_FILE" "$FILES_JSON"

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
  --arg planHash "$PLAN_HASH" \
  '{
    sourcePaths: $sourcePaths,
    outputDir: $outputDir,
    concurrentAgents: $concurrent,
    filesToProcess: $files,
    processedFiles: [],
    pendingFiles: $files,
    startTime: $startTime,
    authorizedPlanHash: $planHash
  }' >"$TEMP"
assert_processor_init_authority "$PLAN_HASH" "$STATE_FILE" "$FILES_JSON"
mv "$TEMP" "$STATE_FILE"
trap - EXIT

echo "✅ Initialized with $(echo "$FILES_JSON" | jq length) files"
