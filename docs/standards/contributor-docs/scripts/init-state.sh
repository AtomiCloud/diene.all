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

# One fail-fast lock serializes every contributor-doc authority mutation in this
# worktree. The lock file is deliberately persistent: only the kernel lock on the
# open descriptor denotes ownership, so there is no stale-file reclamation race.
CONTRIBUTOR_DOCS_LOCK_FD=${CONTRIBUTOR_DOCS_LOCK_FD:-}
CONTRIBUTOR_DOCS_LOCK_ACQUIRED_HERE=0
CONTRIBUTOR_DOCS_TEMP_FILE=${CONTRIBUTOR_DOCS_TEMP_FILE:-}

acquire_authority_lock() {
  local git_dir lock_path

  if [[ -n ${CONTRIBUTOR_DOCS_LOCK_FD:-} ]]; then
    CONTRIBUTOR_DOCS_LOCK_ACQUIRED_HERE=0
    return 0
  fi
  git_dir=$(git rev-parse --absolute-git-dir)
  lock_path="$git_dir/contributor-docs-authority.lock"
  exec {CONTRIBUTOR_DOCS_LOCK_FD}>"$lock_path"
  if ! flock -xn "$CONTRIBUTOR_DOCS_LOCK_FD"; then
    exec {CONTRIBUTOR_DOCS_LOCK_FD}>&-
    CONTRIBUTOR_DOCS_LOCK_FD=
    echo "AUTHORITY_BUSY: contributor-doc authority transaction is active" >&2
    return 1
  fi
  CONTRIBUTOR_DOCS_LOCK_ACQUIRED_HERE=1
}

release_authority_lock() {
  if [[ ${CONTRIBUTOR_DOCS_LOCK_ACQUIRED_HERE:-0} == 1 ]] &&
    [[ -n ${CONTRIBUTOR_DOCS_LOCK_FD:-} ]]; then
    exec {CONTRIBUTOR_DOCS_LOCK_FD}>&-
    CONTRIBUTOR_DOCS_LOCK_FD=
  fi
  CONTRIBUTOR_DOCS_LOCK_ACQUIRED_HERE=0
}

authority_transaction_cleanup() {
  local status=${1:-0}

  if [[ -n ${CONTRIBUTOR_DOCS_TEMP_FILE:-} ]]; then
    rm -f -- "$CONTRIBUTOR_DOCS_TEMP_FILE"
    CONTRIBUTOR_DOCS_TEMP_FILE=
  fi
  release_authority_lock
  return "$status"
}

# Hash a NUL-framed manifest that distinguishes absence, regular bytes, symlink
# targets, directories, and other filesystem object kinds. File length frames the
# byte payload, so arbitrary bytes (including NULs) remain unambiguous.
authority_snapshot() {
  {
    local path size kind target

    printf 'contributor-docs-authority-v1\0'
    for path in "$@"; do
      printf 'path\0%s\0' "$path"
      if [[ -L $path ]]; then
        target=$(readlink -- "$path")
        printf 'symlink\0%s\0%s\0' "${#target}" "$target"
      elif [[ -f $path ]]; then
        size=$(stat -c '%s' -- "$path")
        printf 'regular\0%s\0' "$size"
        cat -- "$path"
        printf '\0'
      elif [[ -d $path ]]; then
        printf 'directory\0'
      elif [[ -e $path ]]; then
        kind=$(stat -c '%F:%f' -- "$path")
        printf 'other\0%s\0' "$kind"
      else
        printf 'absent\0'
      fi
    done
  } | sha256sum | cut -d ' ' -f1
}

append_tree_snapshot_paths() {
  local root=$1 array_name=$2 entry
  local -n destination=$array_name

  destination+=("$root")
  if [[ -d $root && ! -L $root ]]; then
    while IFS= read -r -d '' entry; do
      destination+=("$entry")
    done < <(find -P "$root" -mindepth 1 -print0 | sort -z)
  fi
}

# Snapshot the exact authority files relevant to a processor operation. Write-tier
# completion binds the assigned document. Fact-check operations also bind audit
# state, the epoch sidecar, the assigned document, and the findings tree whose
# canonical artifact the orchestrator just validated.
processor_authority_snapshot() {
  local state_file=$1 assigned_path=${2:-} operation_repo_root=${3:-$REPO_ROOT} state_abs
  local -a paths=(
    "$operation_repo_root/.contributor-docs/task-state.json"
    "$operation_repo_root/.contributor-docs/plan-state.json"
    "$operation_repo_root/.contributor-docs/write-state.json"
    "$operation_repo_root/.contributor-docs/doc-plan.yaml"
    "$operation_repo_root/.contributor-docs/doc-plan.gap-candidate.yaml"
  )

  state_abs=$(realpath -m -- "$state_file")
  if [[ $state_abs == "$operation_repo_root/.contributor-docs/write-tier-"*"/state.json" ]]; then
    if [[ -n $assigned_path ]]; then
      paths+=("$operation_repo_root/$assigned_path")
    fi
  elif [[ $state_abs == "$operation_repo_root/.contributor-docs/fact-check/state.json" ]]; then
    paths+=(
      "$operation_repo_root/.contributor-docs/audit-state.json"
      "$operation_repo_root/.contributor-docs/fact-check/epoch.json"
    )
    if [[ -n $assigned_path ]]; then
      paths+=("$operation_repo_root/$assigned_path")
    fi
    append_tree_snapshot_paths \
      "$operation_repo_root/.contributor-docs/fact-check/findings" paths
  fi
  authority_snapshot "${paths[@]}"
}

processor_write_tier() {
  local state_file_abs prefix suffix tier

  state_file_abs=$(realpath -m -- "$1")
  prefix="$REPO_ROOT/.contributor-docs/write-tier-"
  suffix="/state.json"
  if [[ $state_file_abs != "$prefix"*"$suffix" ]]; then
    return 1
  fi
  tier=${state_file_abs#"$prefix"}
  tier=${tier%"$suffix"}
  [[ $tier =~ ^[1-6]$ ]] || return 1
  printf '%s\n' "$tier"
}

# Internal deterministic contract barrier. It accepts only data paths below the
# declared test root and reads a release token from a FIFO; it never evaluates text
# supplied through the environment.
authority_contract_test_barrier() {
  local point=$1 root ready release root_abs ready_abs release_abs token

  [[ ${CONTRIBUTOR_DOCS_CONTRACT_TEST:-0} == 1 ]] || return 0
  [[ ${CONTRIBUTOR_DOCS_TEST_BARRIER_POINT:-} == "$point" ]] || return 0
  root=${CONTRIBUTOR_DOCS_TEST_ROOT:-}
  ready=${CONTRIBUTOR_DOCS_TEST_READY_FILE:-}
  release=${CONTRIBUTOR_DOCS_TEST_RELEASE_FIFO:-}
  if [[ -z $root || -z $ready || -z $release || ! -d $root || ! -p $release ]]; then
    echo "PROCESSOR_AUTHORITY_INVALID: malformed internal contract barrier" >&2
    return 1
  fi
  root_abs=$(realpath -e -- "$root")
  ready_abs=$(realpath -m -- "$ready")
  release_abs=$(realpath -e -- "$release")
  if [[ $ready_abs != "$root_abs/"* || $release_abs != "$root_abs/"* ]]; then
    echo "PROCESSOR_AUTHORITY_INVALID: contract barrier escaped its test root" >&2
    return 1
  fi
  : >"$ready_abs"
  IFS= read -r token <"$release_abs" || {
    echo "PROCESSOR_AUTHORITY_INVALID: contract barrier release failed" >&2
    return 1
  }
  [[ $token == release ]] || {
    echo "PROCESSOR_AUTHORITY_INVALID: invalid contract barrier release" >&2
    return 1
  }
}

# Canonical pending/committed writer-report law. Runtime helpers and the executable
# reducer import these exact definitions; no caller may substitute a SHA-shaped start
# hash for the processor's durable authorization snapshot.
record_write_jq_source() {
  cat <<'JQ'
def cd_refuse($code): error($code);
def cd_sha256: type == "string" and test("^[0-9a-f]{64}$");
def cd_exact_keys($value; $want):
  ($value | type == "object") and (($value | keys | sort) == ($want | sort));
def cd_normalized_path:
  type == "string" and length > 0 and (startswith("/") | not) and
  (split("/") | all(. != "" and . != "." and . != ".."));
def cd_docs_contains($root; $path):
  ($root | cd_normalized_path) and $root != "." and
  ($path | cd_normalized_path) and ($path | startswith($root + "/"));
def cd_gap_item($root; $gap):
  cd_exact_keys($gap; ["path","type","tier","reason"]) and
  cd_docs_contains($root; $gap.path) and
  ($gap.reason | type == "string" and (gsub("[[:space:]]"; "") | length) > 0) and
  (($gap.type == "concept" and $gap.tier == 2) or
   ($gap.type == "algorithm" and $gap.tier == 3));
def cd_report_shape($root; $report; $path; $plan; $disk; $contained):
  $contained == true and
  cd_exact_keys($report;
    ["reportedBy","authorizedPlanHash","authorizedFromHash","writtenHash","gaps"]) and
  $report.reportedBy == $path and cd_docs_contains($root; $path) and
  $report.authorizedPlanHash == $plan and ($report.authorizedPlanHash | cd_sha256) and
  ($report.authorizedFromHash | cd_sha256) and
  $report.writtenHash == $disk and ($report.writtenHash | cd_sha256) and
  ($report.gaps | type == "array") and
  all($report.gaps[]; cd_gap_item($root; .)) and
  (($report.gaps | map([.path,.type,.tier]) | length) ==
   ($report.gaps | map([.path,.type,.tier]) | unique | length)) and
  ($report.gaps | group_by(.path) |
    all(.[]; (map({type:.type,tier:.tier}) | unique | length) == 1));
def cd_approval_shape($approval; $path; $hash):
  cd_exact_keys($approval; ["path","approvedHash","purpose","approvedAt","consumedAt"]) and
  $approval.path == $path and $approval.purpose == "writer-replay" and
  $approval.approvedHash == $hash and ($approval.approvedHash | cd_sha256) and
  ($approval.approvedAt | type == "string");
def cd_authorization_shape($authorization):
  cd_exact_keys($authorization; ["normalHash","replayApproval"]) and
  ($authorization.normalHash | cd_sha256) and
  (($authorization.replayApproval == null) or
   (cd_exact_keys($authorization.replayApproval; ["ledgerIndex","approvedHash"]) and
    ($authorization.replayApproval.ledgerIndex | type == "number" and floor == . and . >= 0) and
    ($authorization.replayApproval.approvedHash | cd_sha256)));
def cd_derived_written_count($write):
  [$write.writeQueue[] as $path |
    select($write.provenance[$path].writeStatus == "written")] | length;
def cd_record_write_authority($mode; $task; $write; $processor; $tier; $path;
    $report; $plan; $disk; $returned; $contained):
  if ($mode != "pending" and $mode != "committed") then
    cd_refuse("PROCESSOR_AUTHORITY_INVALID")
  elif (($task | type) != "object") or
    (($task.docsRoot | cd_normalized_path) | not) or $task.docsRoot == "." then
    cd_refuse("GAP_REPORT_SET_INVALID")
  elif (($processor | type) != "object") or
    (($processor | has("recordWriteAuthorizations")) | not) or
    (($processor.recordWriteAuthorizations | type) != "object") or
    (($processor.filesToProcess | type) != "array") or
    (($processor.recordWriteAuthorizations | keys_unsorted) != $processor.filesToProcess) or
    (($processor.filesToProcess | index($path)) == null) or
    $processor.authorizedPlanHash != $plan or
    (cd_authorization_shape($processor.recordWriteAuthorizations[$path]) | not) then
    cd_refuse("PROCESSOR_AUTHORITY_INVALID")
  elif (($tier | type) != "number") or ($tier | floor) != $tier or
    $write.step != ("write_tier_" + ($tier | tostring)) or
    $write.currentTier != $tier or $write.authorizedPlanHash != $plan or
    (($write.blockedCollisions | type) != "array") or
    ($write.blockedCollisions | length) != 0 or $write.gapTransition != null or
    (($write.writeQueue | index($path)) == null) or
    $write.provenance[$path].tier != $tier then
    cd_refuse("PROCESSOR_AUTHORITY_INVALID")
  elif (cd_docs_contains($task.docsRoot; $path) | not) or
    (cd_report_shape($task.docsRoot; $report; $path; $plan; $disk; $contained) | not) then
    cd_refuse("GAP_REPORT_SET_INVALID")
  elif $mode == "pending" and ($returned != $disk or $report.writtenHash != $disk) then
    cd_refuse("WRITE_HASH_MISMATCH")
  elif $mode == "pending" and
    ($write.provenance[$path].writeStatus != "pending" or
     $write.provenance[$path].writerReport != null) then
    cd_refuse("WRITE_INCOMPLETE")
  elif $mode == "committed" and
    ($write.provenance[$path].writeStatus != "written" or
     $write.provenance[$path].writtenHash != $disk or
     $write.provenance[$path].writerReport != $report or
     $write.filesWritten != cd_derived_written_count($write)) then
    cd_refuse("WRITE_INCOMPLETE")
  else
    $processor.recordWriteAuthorizations[$path] as $authorization |
    ($authorization.replayApproval // null) as $snapshot_approval |
    (if $snapshot_approval == null then null
     else $write.approvedOverwrites[$snapshot_approval.ledgerIndex] // null end) as $ledger |
    (if $write.provenance[$path].writtenHash != null
     then $write.provenance[$path].writtenHash
     else $write.provenance[$path].scaffoldHash end) as $pending_basis |
    ($report.authorizedFromHash == $authorization.normalHash and
      ($mode == "committed" or $authorization.normalHash == $pending_basis) and
      ($snapshot_approval == null or
       (cd_approval_shape($ledger; $path; $snapshot_approval.approvedHash) and
        $ledger.consumedAt == null))) as $normal |
    ($snapshot_approval != null and
      $report.authorizedFromHash == $snapshot_approval.approvedHash and
      cd_approval_shape($ledger; $path; $snapshot_approval.approvedHash) and
      (if $mode == "pending" then $ledger.consumedAt == null
       else ($ledger.consumedAt | type == "string") end)) as $approval |
    if $normal then "normal"
    elif $approval then "approval:" + ($snapshot_approval.ledgerIndex | tostring)
    else cd_refuse("PROCESSOR_AUTHORITY_INVALID") end
  end;
JQ
}

derive_record_write_authorizations() {
  local state_file=$1 files_json=$2 tier write_state task_state result

  if ! tier=$(processor_write_tier "$state_file"); then
    printf 'null\n'
    return 0
  fi
  write_state="$REPO_ROOT/.contributor-docs/write-state.json"
  task_state="$REPO_ROOT/.contributor-docs/task-state.json"
  if ! result=$(jq -c -n --argjson tier "$tier" --argjson files "$files_json" \
    --slurpfile write "$write_state" --slurpfile task "$task_state" '
      def sha256: type == "string" and test("^[0-9a-f]{64}$");
      def normalized_path:
        type == "string" and length > 0 and (startswith("/") | not) and
        (split("/") | all(. != "" and . != "." and . != ".."));
      def contained($root; $path):
        ($root | normalized_path) and $root != "." and
        ($path | normalized_path) and ($path | startswith($root + "/"));
      ($write[0]) as $state | ($task[0].docsRoot) as $root |
      if (($files | type) != "array") or
        (($files | length) != ($files | unique | length)) or
        (all($files[]; type == "string" and contained($root; .)) | not) or
        $state.step != ("write_tier_" + ($tier | tostring)) or
        $state.currentTier != $tier or
        (($state.blockedCollisions | type) != "array") or
        ($state.blockedCollisions | length) != 0 or $state.gapTransition != null or
        ([ $state.writeQueue[] as $path | $state.provenance[$path] as $entry |
          select($entry.tier == $tier and $entry.writeStatus == "pending") | $path] != $files)
      then error("PROCESSOR_AUTHORITY_INVALID")
      else reduce $files[] as $path ({};
        $state.provenance[$path] as $entry |
        ([range(0; $state.approvedOverwrites | length) as $index |
          $state.approvedOverwrites[$index] as $approval |
          select($approval.path == $path and $approval.purpose == "writer-replay" and
            $approval.consumedAt == null) |
          {ledgerIndex:$index,approvedHash:$approval.approvedHash}] ) as $approvals |
        (if $entry.writtenHash != null then $entry.writtenHash
         else $entry.scaffoldHash end) as $normal |
        if ($normal | sha256 | not) or ($approvals | length) > 1 or
          (all($approvals[]; .approvedHash | sha256) | not)
        then error("PROCESSOR_AUTHORITY_INVALID")
        else .[$path] = {
          normalHash:$normal,
          replayApproval:(if ($approvals | length) == 1 then $approvals[0] else null end)
        } end)
      end
    ' 2>&1); then
    printf '%s\n' "$result" >&2
    echo "PROCESSOR_AUTHORITY_INVALID: cannot derive record-write authorization snapshot" >&2
    return 1
  fi
  printf '%s\n' "$result"
}

reporter_file_identity() {
  local path=$1 mode=$2 task_state docs_root docs_root_abs path_abs

  task_state="$REPO_ROOT/.contributor-docs/task-state.json"
  if ! docs_root=$(jq -er '
      .docsRoot | select(type == "string" and length > 0 and . != "." and
        (startswith("/") | not) and
        (split("/") | all(. != "" and . != "." and . != "..")))
    ' "$task_state" 2>/dev/null); then
    echo "GAP_REPORT_SET_INVALID: invalid docsRoot" >&2
    return 1
  fi
  if ! jq -en --arg root "$docs_root" --arg path "$path" '
      ($path | type == "string" and length > 0 and (startswith("/") | not) and
        (split("/") | all(. != "" and . != "." and . != ".."))) and
      ($path | startswith($root + "/"))
    ' >/dev/null; then
    echo "GAP_REPORT_SET_INVALID: reporter is outside docsRoot" >&2
    return 1
  fi
  if [[ ! -d $REPO_ROOT/$docs_root ]]; then
    echo "GAP_REPORT_SET_INVALID: docsRoot is absent" >&2
    return 1
  fi
  docs_root_abs=$(realpath -e -- "$REPO_ROOT/$docs_root")
  if [[ $docs_root_abs != "$REPO_ROOT/"* ]] || [[ ! -f $REPO_ROOT/$path ]]; then
    if [[ $mode == committed ]]; then
      echo "WRITTEN_BYTES_CHANGED: '${path}' is absent or outside docsRoot" >&2
    else
      echo "WRITE_HASH_MISMATCH: '${path}' is absent or outside docsRoot" >&2
    fi
    return 1
  fi
  path_abs=$(realpath -e -- "$REPO_ROOT/$path")
  if [[ $path_abs != "$docs_root_abs/"* ]] || [[ ! -f $path_abs ]]; then
    echo "GAP_REPORT_SET_INVALID: reporter escapes docsRoot through a symlink" >&2
    return 1
  fi
  sha256sum -- "$path_abs" | cut -d ' ' -f1
}

assert_record_write_authority() {
  local mode=$1 state_file=$2 path=$3 plan_hash=$4 operation_json=${5:-}
  local tier task_state write_state report returned disk expected result program

  if ! tier=$(processor_write_tier "$state_file"); then
    echo "PROCESSOR_AUTHORITY_INVALID: record-write requires an exact write-tier state path" >&2
    return 1
  fi
  assert_plan_authority "$plan_hash"
  task_state="$REPO_ROOT/.contributor-docs/task-state.json"
  write_state="$REPO_ROOT/.contributor-docs/write-state.json"
  if [[ $mode == pending ]]; then
    if ! report=$(jq -ce '.writerReport' <<<"$operation_json" 2>/dev/null) ||
      ! returned=$(jq -er '.returnedHash | select(type == "string")' \
        <<<"$operation_json" 2>/dev/null); then
      echo "GAP_REPORT_SET_INVALID: malformed record-write operation" >&2
      return 1
    fi
  elif [[ $mode == committed ]]; then
    if ! jq -e --arg path "$path" '
        .provenance[$path].writeStatus == "written" and
        (.provenance[$path].writtenHash | type == "string" and test("^[0-9a-f]{64}$"))
      ' "$write_state" >/dev/null; then
      echo "WRITE_INCOMPLETE: '${path}' has no canonical written record" >&2
      return 1
    fi
    report=$(jq -c --arg path "$path" '.provenance[$path].writerReport' "$write_state")
    returned=$(jq -r --arg path "$path" '.provenance[$path].writtenHash' "$write_state")
  else
    echo "PROCESSOR_AUTHORITY_INVALID: unknown record-write view" >&2
    return 1
  fi
  if ! disk=$(reporter_file_identity "$path" "$mode"); then
    return 1
  fi
  if [[ $mode == committed ]]; then
    expected=$(jq -r --arg path "$path" '.provenance[$path].writtenHash' "$write_state")
    if [[ $disk != "$expected" ]]; then
      echo "WRITTEN_BYTES_CHANGED: '${path}' expected=${expected} actual=${disk}" >&2
      return 1
    fi
  fi
  program=$(record_write_jq_source)
  if ! result=$(jq -n -r \
    --slurpfile task "$task_state" --slurpfile write "$write_state" \
    --slurpfile processor "$state_file" --arg mode "$mode" --argjson tier "$tier" \
    --arg path "$path" --arg plan "$plan_hash" --arg disk "$disk" \
    --arg returned "$returned" --argjson report "$report" \
    "$program
      cd_record_write_authority(\$mode; \$task[0]; \$write[0]; \$processor[0];
        \$tier; \$path; \$report; \$plan; \$disk; \$returned; true)" 2>&1); then
    printf '%s\n' "$result" >&2
    return 1
  fi
  printf '%s\n' "$result"
}

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
      and ($plan.indexes | type == "array")
      and all(plan_entries($plan)[];
        (.entry.path | normalized_path(.)) and
        ((.entry.crossLinks // {}) | type == "object") and
        all((.entry.crossLinks // {})[];
          type == "array" and all(.[]; normalized_path(.))));
    def plan_links($plan):
      [plan_entries($plan)[] as $wrapped |
        (($wrapped.entry.crossLinks // {}) | to_entries[]) as $links |
        $links.value[] as $target |
        {reportedBy:$wrapped.outputPath,field:$links.key,
         target:($plan.docsRoot + "/" + $target)}] |
      sort_by([.reportedBy,.field,.target]) | unique_by([.reportedBy,.field,.target]);
    def dirname($path):
      $path | split("/") | .[0:length - 1] | join("/");
    def as_set($items):
      reduce $items[] as $item ({}; .[$item] = true);
    def index_paths($plan):
      [plan_entries($plan)[] |
        select(.container == "indexes" or .entry.type == "index") |
        .outputPath] | unique;
    def reverse_adjacency($links; $queue_set):
      reduce ($links[] | select($queue_set[.reportedBy] != null)) as $link
        ({}; .[$link.target] += [$link.reportedBy]);
    def directory_indexes($indexes; $queue_set):
      reduce ($indexes[] | select($queue_set[.] != null)) as $index
        ({}; .[dirname($index)] += [$index]);
    def closure_set($reverse; $directory; $gaps; $reporters; $queue_set):
      {reached:as_set($reporters | map(select($queue_set[.] != null))),
       frontier:(($reporters + $gaps) | unique)} |
      until((.frontier | length) == 0;
        .reached as $reached |
        ([.frontier[] as $path | (($reverse[$path] // [])[])] +
         [.frontier[] as $path | (($directory[dirname($path)] // [])[])] |
          unique) as $candidates |
        ($candidates | map(select($reached[.] == null))) as $new |
        {reached:(reduce $new[] as $path ($reached; .[$path] = true)),
         frontier:$new}) |
      .reached | keys;
    def expected_requeued($record; $queue; $live; $later_links; $later_paths):
      as_set($queue - $later_paths) as $queue_set |
      reverse_adjacency(plan_links($live) - $later_links; $queue_set) as $reverse |
      directory_indexes(index_paths($live); $queue_set) as $directory |
      ($record.gapPaths | map(.path) | unique) as $gaps |
      (closure_set($reverse; $directory; $gaps;
        ($record.reports | map(.reportedBy) | unique); $queue_set) - $gaps) |
      sort;
    def expected_replay_tier($record; $provenance):
      (($record.gapPaths | map(.tier)) +
       [$record.requeued[] as $path | $provenance[$path].tier]) | min;
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
    def closed_record($value; $write; $live; $later):
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
      and ($value.requeued | type == "array" and length > 0)
      and all($value.requeued[]; . as $path |
        ($path | normalized_path(.)) and ($write.writeQueue | index($path)) != null and
        ($write.provenance[$path].tier | type == "number" and floor == . and . >= 1 and . <= 6))
      and ($value.requeued | length) == ($value.requeued | unique | length)
      and all($value.reports[].reportedBy; . as $path | ($value.requeued | index($path)) != null)
      and all($value.requeued[];
        . as $path | ($value.gapPaths | map(.path) | index($path)) == null)
      and $value.requeued == expected_requeued($value; $write.writeQueue; $live;
        [$later[] | (.planMutation.addedCrossLinks // [])[]];
        [$later[] | (.gapPaths // [])[] | .path])
      and $value.replayTier == expected_replay_tier($value; $write.provenance)
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
    elif ([ $write.gapsResolved[] | [(.gapPaths // [])[] | .path] | unique[] ]) as $closed_paths |
      ($closed_paths | length) != ($closed_paths | unique | length)
    then "GAP_LOOP"
    elif (([range(0; $write.gapsResolved | length)] | all(. as $index |
        closed_record($write.gapsResolved[$index]; $write; $live;
          $write.gapsResolved[$index:]))) and
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
  local expected_hash=$1 state_file=$2 files_json=$3 authorizations

  if ! assert_plan_authority "$expected_hash"; then
    return 1
  fi
  if ! authorizations=$(derive_record_write_authorizations "$state_file" "$files_json"); then
    echo "PROCESSOR_AUTHORITY_INVALID: current tier, collision set, pending slice, or approval ledger changed" >&2
    return 1
  fi
  printf '%s\n' "$authorizations"
}

init_state_main() {
if [[ ${1:-} == "--assert-plan-authority" ]]; then
  [[ $# -ge 2 ]] || {
    echo "❌ Usage: init-state.sh --assert-plan-authority <plan-hash> [plan-state] [write-state] [live-plan] [candidate-plan]" >&2
    exit 1
  }
  assert_plan_authority "$2" "${3:-}" "${4:-}" "${5:-}" "${6:-}"
  exit 0
fi

if [[ ${1:-} == "--assert-record-write" ]]; then
  [[ $# -eq 5 && ($2 == pending || $2 == committed) && $5 =~ ^[0-9a-f]{64}$ ]] || {
    echo "❌ Usage: init-state.sh --assert-record-write <pending|committed> <state-file> <path> <plan-hash>" >&2
    exit 1
  }
  if [[ $2 == pending ]]; then
    RECORD_WRITE_OPERATION=$(jq -c '.') || {
      echo "GAP_REPORT_SET_INVALID: malformed record-write operation" >&2
      exit 1
    }
  else
    RECORD_WRITE_OPERATION=
  fi
  assert_record_write_authority "$2" "$3" "$4" "$5" "$RECORD_WRITE_OPERATION"
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

  wait_for_contract_barrier() {
    local ready=$1 index

    for ((index = 0; index < 1000; index++)); do
      [[ -e $ready ]] && return 0
      sleep 0.01
    done
    return 1
  }

  processor_fixture_manifest() {
    local fixture_repo=$1 processor_state=$2 assigned_path=${3:-}

    {
      processor_authority_snapshot "$processor_state" "$assigned_path" "$fixture_repo"
      authority_snapshot "$processor_state"
    } | sha256sum | cut -d ' ' -f1
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


  record_write_jq_source >"$CONTROL_DIR/record-write.jq"
  cat >"$CONTROL_DIR/reducer.jq" <<'JQ'
	include "record-write";
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
	def ledger_reports($state):
	  [$state.writeQueue[] as $path | $state.provenance[$path] as $entry |
	    select($entry.tier == $state.currentTier and $entry.writeStatus == "written") |
	    if cd_record_write_authority("committed"; $state.taskState; $state;
	      $state.processorState; $state.currentTier; $path; $entry.writerReport;
	      $state.authorizedPlanHash; $entry.writtenHash; $entry.writtenHash; true)
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
	def parse_plan($bytes): try ($bytes | fromjson) catch refuse("GAP_PLAN_DELTA_INVALID");
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
	def valid_plan($plan):
	  exact_keys($plan; ["docsRoot","modules","shared","topLevel","adrs","indexes"])
	  and ($plan.docsRoot | normalized_path(.))
	  and ($plan.modules | type == "array")
	  and all($plan.modules[];
	    exact_keys(.; ["name","description","files"])
	    and (.name | type == "string" and length > 0)
	    and (.description | type == "string") and (.files | type == "array"))
	  and exact_keys($plan.shared; ["files"]) and ($plan.shared.files | type == "array")
	  and ($plan.topLevel | type == "array")
	  and ($plan.adrs | type == "array") and ($plan.indexes | type == "array")
	  and all(plan_entries($plan)[];
	    (.entry.path | normalized_path(.)) and
	    ((.entry.crossLinks // {}) | type == "object") and
	    all((.entry.crossLinks // {})[];
	      type == "array" and all(.[]; normalized_path(.))));
	def plan_links($plan):
	  [plan_entries($plan)[] as $wrapped |
	    (($wrapped.entry.crossLinks // {}) | to_entries[]) as $links |
	    $links.value[] as $target |
	    {reportedBy:$wrapped.outputPath,field:$links.key,
	     target:($plan.docsRoot + "/" + $target)}] |
	  sort_by([.reportedBy,.field,.target]) | unique_by([.reportedBy,.field,.target]);
	def dirname($path):
	  $path | split("/") | .[0:length - 1] | join("/");
	def as_set($items):
	  reduce $items[] as $item ({}; .[$item] = true);
	def index_paths($plan):
	  [plan_entries($plan)[] |
	    select(.container == "indexes" or .entry.type == "index") |
	    .outputPath] | unique;
	def reverse_adjacency($links; $queue_set):
	  reduce ($links[] | select($queue_set[.reportedBy] != null)) as $link
	    ({}; .[$link.target] += [$link.reportedBy]);
	def directory_indexes($indexes; $queue_set):
	  reduce ($indexes[] | select($queue_set[.] != null)) as $index
	    ({}; .[dirname($index)] += [$index]);
	def closure_set($reverse; $directory; $gaps; $reporters; $queue_set):
	  {reached:as_set($reporters | map(select($queue_set[.] != null))),
	   frontier:(($reporters + $gaps) | unique)} |
	  until((.frontier | length) == 0;
	    .reached as $reached |
	    ([.frontier[] as $path | (($reverse[$path] // [])[])] +
	     [.frontier[] as $path | (($directory[dirname($path)] // [])[])] |
	      unique) as $candidates |
	    ($candidates | map(select($reached[.] == null))) as $new |
	    {reached:(reduce $new[] as $path ($reached; .[$path] = true)),
	     frontier:$new}) |
	  .reached | keys;
	def expected_requeued($record; $queue; $live; $later_links; $later_paths):
	  as_set($queue - $later_paths) as $queue_set |
	  reverse_adjacency(plan_links($live) - $later_links; $queue_set) as $reverse |
	  directory_indexes(index_paths($live); $queue_set) as $directory |
	  ($record.gapPaths | map(.path) | unique) as $gaps |
	  (closure_set($reverse; $directory; $gaps;
	    ($record.reports | map(.reportedBy) | unique); $queue_set) - $gaps) |
	  sort;
	def expected_replay_tier($record; $provenance):
	  (($record.gapPaths | map(.tier)) +
	   [$record.requeued[] as $path | $provenance[$path].tier]) | min;
	def closed_record($closed; $state; $later):
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
	  and ($closed.requeued | type == "array" and length > 0)
	  and all($closed.requeued[]; . as $path |
	    ($path | normalized_path(.)) and ($state.writeQueue | index($path)) != null and
	    ($state.provenance[$path].tier | type == "number" and floor == . and . >= 1 and . <= 6))
	  and ($closed.requeued | length) == ($closed.requeued | unique | length)
	  and all($closed.reports[].reportedBy; . as $path | ($closed.requeued | index($path)) != null)
	  and all($closed.requeued[];
	    . as $path | ($closed.gapPaths | map(.path) | index($path)) == null)
	  and $closed.requeued == expected_requeued($closed; $state.writeQueue; $state.livePlan;
	    [$later[] | (.planMutation.addedCrossLinks // [])[]] +
	      (($state.gapPlanMutation.addedCrossLinks) // []);
	    [$later[] | (.gapPaths // [])[] | .path] +
	      ((($state.gapRecord.gapPaths) // []) | map(.path)))
	  and $closed.replayTier == expected_replay_tier($closed; $state.provenance)
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
	    ($state.canonicalCandidatePath | type == "string") and
	    valid_plan($state.livePlan) and
	    all($state.gapsResolved[]; (.planMutation.addedCrossLinks // [])[] as $link |
	      (plan_links($state.livePlan) | index($link)) != null) then
	    ([ $state.gapsResolved[] | [(.gapPaths // [])[] | .path] | unique[] ]) as $closed_paths |
	    if (($closed_paths | length) != ($closed_paths | unique | length) or
	       any((($state.gapRecord.gapPaths // [])[]);
	         .path as $path | ($closed_paths | index($path)) != null))
	    then refuse("GAP_LOOP")
	    elif (([range(0; $state.gapsResolved | length)] | all(. as $index |
	        closed_record($state.gapsResolved[$index]; $state;
	          $state.gapsResolved[$index:]))) and
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
	    ($state.candidateHash // null) == null and
	    ($state.candidatePlan // null) == null then
	    $state
	  elif (["planned","prepared","scaffolded","reset","cleaned"] | index($state.gapStatus)) != null and
	    stored_mutation($state.gapPlanMutation; $state.canonicalCandidatePath;
	      $state.gapRecord.reports; $state.gapRecord.gapPaths) and
	    $state.gapPlanMutation.fromPlanHash == $cursor and
	    $state.authorizedPlanHash == $state.gapPlanMutation.toPlanHash and
	    $state.livePlanHash == $state.authorizedPlanHash and
	    ($state.candidateHash // null) == null and
	    ($state.candidatePlan // null) == null then
	    $state
	  else refuse("PLAN_DRIFT_BLOCKED") end;
	def plan_skeleton($plan):
	  $plan | .modules = [.modules[] | .files = []] | .shared.files = [] |
	  .topLevel = [] | .adrs = [] | .indexes = [];
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
	    else parse_plan($data.livePlanBytes) as $live_plan |
	      parse_plan($data.candidatePlanBytes) as $candidate_plan |
	      if $live_plan != $state.livePlan then refuse("PLAN_DRIFT_BLOCKED")
	      else derive_mutation($state; $data; $reports; $gap_paths) as $mutation |
	        ({gapPaths:$gap_paths,reports:$reports} |
	          expected_requeued(.; $state.writeQueue; $live_plan; []; [])) as $requeued |
	        ((($gap_paths | map(.tier)) +
	          [$requeued[] as $path | $state.provenance[$path].tier])) as $tiers |
	        if $mutation.fromPlanHash != $cursor or
	          $state.candidateHash != $mutation.toPlanHash then refuse("GAP_PLAN_HASH_INVALID")
	        else $state | .gapStatus = "enqueued" | .gapPlanMutation = $mutation |
	          .candidatePlan = $candidate_plan |
	          .gapRecord = {
	            status:"enqueued",reports:$reports,gapPaths:$gap_paths,
	            expectedScaffold:{},replayTier:($tiers | min),
	            requeued:$requeued,resetTiers:($tiers | sort | unique),
	            cleanedTiers:[],openedAt:$data.openedAt,planMutation:$mutation
	          }
	        end
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
	      ($state.candidateHash // null) == null and
	      ($state.candidatePlan // null) == null then $state
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
	        .livePlan = .candidatePlan | .candidatePlan = null |
	        .candidateHash = null | .gapStatus = "planned" | .gapRecord.status = "planned"
	    elif $state.livePlanHash == gap_mutation($state).toPlanHash and
	      ($state.candidateHash // null) == null and
	      ($state.candidatePlan // null) == null then
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
	      ((try cd_record_write_authority("committed"; $state.taskState; $state;
	        $state.processorState; $state.currentTier; $path; $entry.writerReport;
	        $state.authorizedPlanHash; $entry.writtenHash; $entry.writtenHash; true)
	        catch false) | not))
	      then refuse("WRITE_REPORT_MISSING")
	    else $state | .step = "completed" end
	  elif $operation == "record-write" then
	    current_plan($state) |
	    if $data.returnedHash != $data.diskHash then refuse("WRITE_HASH_MISMATCH")
	    elif ($data.path | type != "string") or (($state.writeQueue | index($data.path)) == null) or
	      ($state.provenance[$data.path] == null) or
	      $state.provenance[$data.path].writeStatus != "pending" then refuse("WRITE_INCOMPLETE")
	    else
	      ($data | if has("reporterContained") then .reporterContained else true end) as $contained |
	      cd_record_write_authority("pending"; $state.taskState; $state;
	        $state.processorState; $state.currentTier; $data.path; $data.writerReport;
	        $state.authorizedPlanHash; $data.diskHash; $data.returnedHash; $contained) as $branch |
	      ($state |
	        .provenance[$data.path].writeStatus = "written" |
	        .provenance[$data.path].writtenHash = $data.diskHash |
	        .provenance[$data.path].writerReport = $data.writerReport |
	        .pending -= [$data.path] |
	        .filesWritten = cd_derived_written_count(.) |
	        if ($branch | startswith("approval:")) then
	          .approvedOverwrites[($branch | ltrimstr("approval:") | tonumber)].consumedAt =
	            $data.consumedAt
	        else . end) as $next |
	      cd_record_write_authority("committed"; $next.taskState; $next;
	        $next.processorState; $next.currentTier; $data.path; $data.writerReport;
	        $next.authorizedPlanHash; $data.diskHash; $data.returnedHash; $contained) as $committed |
	      if $committed == $branch then $next else refuse("PROCESSOR_AUTHORITY_INVALID") end
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
	      if (closed_record($closed; $state; []) | not)
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
  COMPLEX_BASE_PLAN_BYTES=$(jq -cn '{
	    docsRoot:"docs",
	    modules:[{name:"orders",description:"Order documentation",files:[
	      {path:"r.mdx",type:"feature",tier:4,description:"Reporter",
	       sources:["src/r.ts"],crossLinks:{concepts:[],algorithms:[]},tags:["orders"]},
	      {path:"dep.mdx",type:"algorithm",tier:3,description:"Depends on reporter",
	       sources:["src/dep.ts"],crossLinks:{concepts:["r.mdx"],algorithms:[]},tags:["orders"]},
	      {path:"top.mdx",type:"module-overview",tier:1,description:"Depends on dependency",
	       sources:["src/top.ts"],crossLinks:{concepts:[],algorithms:["dep.mdx"]},tags:["orders"]},
	      {path:"nav.mdx",type:"surface",tier:5,description:"Depends on area index",
	       sources:["src/nav.ts"],crossLinks:{concepts:["area/index.mdx"],algorithms:[]},tags:["orders"]},
	      {path:"unrelated.mdx",type:"feature",tier:4,description:"Unaffected queued file",
	       sources:["src/unrelated.ts"],crossLinks:{concepts:[],algorithms:[]},tags:["orders"]}
	    ]}],
	    shared:{files:[]},topLevel:[],adrs:[],indexes:[{
	      path:"area/index.mdx",type:"index",tier:6,description:"Area index",
	      sources:["src/area.ts"],crossLinks:{concepts:[],algorithms:[]},tags:["orders"]
	    }]
	  }')
  COMPLEX_PLAN_BYTES=$(jq -c '
	    .modules[0].files[0].crossLinks.concepts = ["area/gap.mdx"] |
	    .shared.files = [{
	      path:"area/gap.mdx",type:"concept",tier:2,description:"Discovered area concept",
	      sources:["src/r.ts"],crossLinks:{concepts:[],algorithms:[]},tags:["orders"]
	    }]
	  ' <<<"$COMPLEX_BASE_PLAN_BYTES")
  PLAN_A=$(printf '%s' "$LIVE_PLAN_BYTES" | sha256sum | cut -d ' ' -f1)
  PLAN_B=$(printf '%s' "$CANDIDATE_PLAN_BYTES" | sha256sum | cut -d ' ' -f1)
  PLAN_C=$(printf '%s' "$SECOND_PLAN_BYTES" | sha256sum | cut -d ' ' -f1)
  COMPLEX_PLAN_ROOT=$(printf '%s' "$COMPLEX_BASE_PLAN_BYTES" | sha256sum | cut -d ' ' -f1)
  COMPLEX_PLAN_FINAL=$(printf '%s' "$COMPLEX_PLAN_BYTES" | sha256sum | cut -d ' ' -f1)
  UNRELATED_HASH=$(printf '%s' "$UNRELATED_PLAN_BYTES" | sha256sum | cut -d ' ' -f1)
  FILE_BYTES='complete writer output'
  FILE_HASH=$(printf '%s' "$FILE_BYTES" | sha256sum | cut -d ' ' -f1)
  FROM_HASH=eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee
  SCAFFOLD_A=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
  SCAFFOLD_B=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
  BASE_STATE=$(jq -cn --arg hash "$PLAN_A" --arg fileHash "$FILE_HASH" \
    --arg fromHash "$FROM_HASH" --arg candidate "$CONTRACT_CANDIDATE_PATH" \
    --argjson livePlan "$LIVE_PLAN_BYTES" '{
	      step:"scaffold",pending:[],writeQueue:["docs/r.mdx"],currentTier:4,gapStatus:null,
	      taskState:{docsRoot:"docs"},approvedOverwrites:[],blockedCollisions:[],
	      gapTransition:null,filesWritten:1,
	      planStateHash:$hash,approvedPlanHash:$hash,authorizedPlanHash:$hash,livePlanHash:$hash,
	      candidateHash:null,candidatePlan:null,canonicalCandidatePath:$candidate,
	      livePlan:$livePlan,gapsResolved:[],
	      gapPlanMutation:null,gapRecord:null,
	      processorState:{
	        filesToProcess:["docs/r.mdx"],pendingFiles:["docs/r.mdx"],processedFiles:[],
	        authorizedPlanHash:$hash,
	        recordWriteAuthorizations:{
	          "docs/r.mdx":{normalHash:$fromHash,replayApproval:null}
	        }
	      },
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
  COMPLEX_STORED_MUTATION=$(jq -cn --arg from "$COMPLEX_PLAN_ROOT" \
    --arg to "$COMPLEX_PLAN_FINAL" --arg candidate "$CONTRACT_CANDIDATE_PATH" \
    --argjson plan "$COMPLEX_PLAN_BYTES" '{
	      fromPlanHash:$from,toPlanHash:$to,candidatePath:$candidate,
	      addedPlanEntries:[{
	        outputPath:"docs/area/gap.mdx",container:"shared",entry:$plan.shared.files[0]
	      }],
	      addedCrossLinks:[{
	        reportedBy:"docs/r.mdx",field:"concepts",target:"docs/area/gap.mdx"
	      }]
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
  COMPLEX_CLOSED_RECORD=$(jq -cn --argjson mutation "$COMPLEX_STORED_MUTATION" \
    --arg scaffold "$SCAFFOLD_A" '{
	      status:"cleared",reports:[{reportedBy:"docs/r.mdx",gaps:[{
	        path:"docs/area/gap.mdx",type:"concept",tier:2,
	        reason:"Reporter needs the area concept"
	      }]}],gapPaths:[{path:"docs/area/gap.mdx",type:"concept",tier:2}],
	      expectedScaffold:{"docs/area/gap.mdx":$scaffold},replayTier:1,
	      requeued:["docs/area/index.mdx","docs/dep.mdx","docs/nav.mdx","docs/r.mdx","docs/top.mdx"],
	      resetTiers:[1,2,3,4,5,6],cleanedTiers:[1,2,3,4,5,6],
	      openedAt:"2026-08-01T00:02:00Z",planMutation:$mutation,
	      closedAt:"2026-08-01T00:02:01Z"
	    }')
  ENQUEUED_STATE=$(jq -c --arg hash "$PLAN_B" --argjson mutation "$STORED_PLAN_MUTATION" \
    --argjson record "$GAP_RECORD" --argjson candidatePlan "$CANDIDATE_PLAN_BYTES" '
	      .candidateHash = $hash | .gapStatus = "enqueued" | .gapPlanMutation = $mutation |
	      .candidatePlan = $candidatePlan | .gapRecord = $record
	    ' <<<"$BASE_STATE")
  PLANNED_STATE=$(jq -c --arg hash "$PLAN_B" --argjson livePlan "$CANDIDATE_PLAN_BYTES" '
	    .candidateHash = null | .authorizedPlanHash = $hash | .livePlanHash = $hash |
	    .candidatePlan = null | .livePlan = $livePlan |
	    .gapStatus = "planned" | .gapRecord.status = "planned"
	  ' <<<"$ENQUEUED_STATE")

  CONTROL_FAILURES_BEFORE=$FAILURES
  COMPLEX_PRODUCER_REPORT=$(jq -cn --arg plan "$COMPLEX_PLAN_ROOT" \
    --arg from "$SCAFFOLD_A" --arg written "$FILE_HASH" '{
      reportedBy:"docs/r.mdx",authorizedPlanHash:$plan,authorizedFromHash:$from,
      writtenHash:$written,gaps:[{
        path:"docs/area/gap.mdx",type:"concept",tier:2,
        reason:"Reporter needs the area concept"
      }]
    }')
  COMPLEX_PRODUCER_STATE=$(jq -c --arg root "$COMPLEX_PLAN_ROOT" \
    --arg final "$COMPLEX_PLAN_FINAL" --arg scaffold "$SCAFFOLD_A" \
    --arg written "$FILE_HASH" --argjson report "$COMPLEX_PRODUCER_REPORT" \
    --argjson livePlan "$COMPLEX_BASE_PLAN_BYTES" '
      .step = "write_tier_4" | .currentTier = 4 |
      .planStateHash = $root | .approvedPlanHash = $root |
      .authorizedPlanHash = $root | .livePlanHash = $root | .livePlan = $livePlan |
      .candidateHash = $final | .candidatePlan = null | .gapStatus = null |
      .gapPlanMutation = null | .gapRecord = null | .gapsResolved = [] |
      .filesWritten = 1 |
      .writeQueue = [
        "docs/r.mdx","docs/dep.mdx","docs/top.mdx","docs/nav.mdx",
        "docs/unrelated.mdx","docs/area/index.mdx"
      ] |
      .provenance = {
        "docs/r.mdx":{tier:4,writeStatus:"written",scaffoldHash:$scaffold,
          writtenHash:$written,writerReport:$report},
        "docs/dep.mdx":{tier:3,writeStatus:"pending",scaffoldHash:$scaffold,
          writtenHash:null,writerReport:null},
        "docs/top.mdx":{tier:1,writeStatus:"pending",scaffoldHash:$scaffold,
          writtenHash:null,writerReport:null},
        "docs/nav.mdx":{tier:5,writeStatus:"pending",scaffoldHash:$scaffold,
          writtenHash:null,writerReport:null},
        "docs/unrelated.mdx":{tier:4,writeStatus:"pending",scaffoldHash:$scaffold,
          writtenHash:null,writerReport:null},
        "docs/area/index.mdx":{tier:6,writeStatus:"pending",scaffoldHash:$scaffold,
          writtenHash:null,writerReport:null}
      } |
      .processorState = {
        filesToProcess:["docs/r.mdx"],pendingFiles:[],processedFiles:["docs/r.mdx"],
        authorizedPlanHash:$root,
        recordWriteAuthorizations:{
          "docs/r.mdx":{normalHash:$scaffold,replayApproval:null}
        }
      }
    ' <<<"$BASE_STATE")
  COMPLEX_PRODUCER_INPUT=$(jq -cn --arg live "$COMPLEX_BASE_PLAN_BYTES" \
    --arg candidate "$COMPLEX_PLAN_BYTES" '{
      livePlanBytes:$live,candidatePlanBytes:$candidate,
      openedAt:"2026-08-01T00:02:00Z"
    }')
  if ! COMPLEX_PRODUCED=$(jq -n -L "$CONTROL_DIR" \
    --argjson state "$COMPLEX_PRODUCER_STATE" --arg operation authorize-gap-plan \
    --argjson data "$COMPLEX_PRODUCER_INPUT" -f "$CONTROL_DIR/reducer.jq") ||
    ! jq -e '
      .gapRecord.requeued == [
        "docs/area/index.mdx","docs/dep.mdx","docs/nav.mdx","docs/r.mdx","docs/top.mdx"
      ] and .gapRecord.replayTier == 1 and
      .gapRecord.resetTiers == [1,2,3,4,5,6]
    ' <<<"$COMPLEX_PRODUCED" >/dev/null; then
    contract_failure 'authorize-gap-plan did not derive the exact transitive/index closure and tiers'
  fi
  if [[ $FAILURES -eq $CONTROL_FAILURES_BEFORE ]]; then
    echo '✅ authorize-gap-plan produced the exact transitive/index closure, replay tier, and reset tiers'
  fi

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
    .filesWritten = 0 |
    .provenance["docs/r.mdx"].writeStatus = "pending" |
    .provenance["docs/r.mdx"].writtenHash = null |
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

  REPORT_PATH_CASES=(
    /abs.mdx
    ../escape.mdx
    docs/../escape.mdx
    docs//x.mdx
    docs2/lookalike.mdx
    docs/.
    outside/x.mdx
  )
  for REPORT_PATH in "${REPORT_PATH_CASES[@]}"; do
    BAD_PATH_REPORT=$(jq -c --arg path "$REPORT_PATH" '.gaps[0].path = $path' \
      <<<"$WRITE_REPORT_VALID")
    BAD_PATH_DATA=$(jq -cn --arg hash "$FILE_HASH" --argjson report "$BAD_PATH_REPORT" '{
      path:"docs/r.mdx",returnedHash:$hash,diskHash:$hash,writerReport:$report
    }')
    if OUTPUT=$(jq -n -L "$CONTROL_DIR" --argjson state "$PENDING_WRITE_STATE" \
      --arg operation record-write --argjson data "$BAD_PATH_DATA" \
      -f "$CONTROL_DIR/reducer.jq" 2>&1); then
      contract_failure "Out-of-root or unnormalized gap path was accepted: ${REPORT_PATH}"
    elif [[ $OUTPUT != *GAP_REPORT_SET_INVALID* ]]; then
      contract_failure "Invalid gap path failed with the wrong refusal: ${REPORT_PATH}"
    fi
  done
  ESCAPED_REPORTER_DATA=$(jq -c '.reporterContained = false' <<<"$WRITE_DATA_VALID")
  if OUTPUT=$(jq -n -L "$CONTROL_DIR" --argjson state "$PENDING_WRITE_STATE" \
    --arg operation record-write --argjson data "$ESCAPED_REPORTER_DATA" \
    -f "$CONTROL_DIR/reducer.jq" 2>&1); then
    contract_failure 'Symlink-escaped reporter witness was accepted by the shared report law'
  elif [[ $OUTPUT != *GAP_REPORT_SET_INVALID* ]]; then
    contract_failure 'Symlink-escaped reporter witness failed with the wrong refusal'
  fi

  RANDOM_START_REPORT=$(jq -c \
    '.authorizedFromHash = "dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd"' \
    <<<"$WRITE_REPORT_VALID")
  RANDOM_START_DATA=$(jq -cn --arg hash "$FILE_HASH" --argjson report "$RANDOM_START_REPORT" '{
    path:"docs/r.mdx",returnedHash:$hash,diskHash:$hash,writerReport:$report
  }')
  if OUTPUT=$(jq -n -L "$CONTROL_DIR" --argjson state "$PENDING_WRITE_STATE" \
    --arg operation record-write --argjson data "$RANDOM_START_DATA" \
    -f "$CONTROL_DIR/reducer.jq" 2>&1); then
    contract_failure 'Random SHA-shaped writer start authority was accepted'
  elif [[ $OUTPUT != *PROCESSOR_AUTHORITY_INVALID* ]]; then
    contract_failure 'Random writer start authority failed with the wrong refusal'
  fi

  RETAINED_HASH=abababababababababababababababababababababababababababababababab
  OTHER_NORMAL_HASH=cdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcd
  RETAINED_REPORT=$(jq -c --arg from "$RETAINED_HASH" '.authorizedFromHash = $from' \
    <<<"$WRITE_REPORT_VALID")
  RETAINED_DATA=$(jq -cn --arg hash "$FILE_HASH" --argjson report "$RETAINED_REPORT" '{
    path:"docs/r.mdx",returnedHash:$hash,diskHash:$hash,writerReport:$report
  }')
  RETAINED_MISMATCH_STATE=$(jq -c --arg retained "$RETAINED_HASH" \
    --arg other "$OTHER_NORMAL_HASH" '
      .provenance["docs/r.mdx"].writtenHash = $retained |
      .processorState.recordWriteAuthorizations["docs/r.mdx"].normalHash = $other
    ' <<<"$PENDING_WRITE_STATE")
  if OUTPUT=$(jq -n -L "$CONTROL_DIR" --argjson state "$RETAINED_MISMATCH_STATE" \
    --arg operation record-write --argjson data "$RETAINED_DATA" \
    -f "$CONTROL_DIR/reducer.jq" 2>&1); then
    contract_failure 'Retained replay hash absent from the processor snapshot was accepted'
  elif [[ $OUTPUT != *PROCESSOR_AUTHORITY_INVALID* ]]; then
    contract_failure 'Mismatched retained replay snapshot failed with the wrong refusal'
  fi

  APPROVED_HASH=dededededededededededededededededededededededededededededededede
  APPROVAL_REPORT=$(jq -c --arg from "$APPROVED_HASH" '.authorizedFromHash = $from' \
    <<<"$WRITE_REPORT_VALID")
  APPROVAL_DATA=$(jq -cn --arg hash "$FILE_HASH" --argjson report "$APPROVAL_REPORT" '{
    path:"docs/r.mdx",returnedHash:$hash,diskHash:$hash,writerReport:$report,
    consumedAt:"2026-08-01T00:04:00Z"
  }')
  APPROVAL_PENDING_STATE=$(jq -c --arg approved "$APPROVED_HASH" '
    .approvedOverwrites = [{
      path:"docs/r.mdx",approvedHash:$approved,purpose:"writer-replay",
      approvedAt:"2026-08-01T00:03:00Z",consumedAt:null
    }] |
    .processorState.recordWriteAuthorizations["docs/r.mdx"].replayApproval = {
      ledgerIndex:0,approvedHash:$approved
    }
  ' <<<"$PENDING_WRITE_STATE")
  if ! APPROVAL_WRITTEN=$(jq -n -L "$CONTROL_DIR" \
    --argjson state "$APPROVAL_PENDING_STATE" --arg operation record-write \
    --argjson data "$APPROVAL_DATA" -f "$CONTROL_DIR/reducer.jq") ||
    ! jq -e --argjson report "$APPROVAL_REPORT" '
      .approvedOverwrites[0].consumedAt == "2026-08-01T00:04:00Z" and
      .provenance["docs/r.mdx"].writerReport == $report
    ' <<<"$APPROVAL_WRITTEN" >/dev/null; then
    contract_failure 'Exact unconsumed replay approval was not consumed and committed atomically'
  fi

  APPROVAL_BAD_INDEX=$(jq -c '
    .processorState.recordWriteAuthorizations["docs/r.mdx"].replayApproval.ledgerIndex = 1
  ' <<<"$APPROVAL_PENDING_STATE")
  APPROVAL_BAD_PATH=$(jq -c '.approvedOverwrites[0].path = "docs/other.mdx"' \
    <<<"$APPROVAL_PENDING_STATE")
  APPROVAL_BAD_PURPOSE=$(jq -c '.approvedOverwrites[0].purpose = "scaffold"' \
    <<<"$APPROVAL_PENDING_STATE")
  APPROVAL_BAD_HASH=$(jq -c \
    '.approvedOverwrites[0].approvedHash = "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"' \
    <<<"$APPROVAL_PENDING_STATE")
  APPROVAL_ALREADY_CONSUMED=$(jq -c \
    '.approvedOverwrites[0].consumedAt = "2026-08-01T00:03:30Z"' \
    <<<"$APPROVAL_PENDING_STATE")
  APPROVAL_CASE_NAMES=(APPROVAL_BAD_INDEX APPROVAL_BAD_PATH APPROVAL_BAD_PURPOSE
    APPROVAL_BAD_HASH APPROVAL_ALREADY_CONSUMED)
  APPROVAL_CASE_VALUES=("$APPROVAL_BAD_INDEX" "$APPROVAL_BAD_PATH" "$APPROVAL_BAD_PURPOSE"
    "$APPROVAL_BAD_HASH" "$APPROVAL_ALREADY_CONSUMED")
  for APPROVAL_CASE_INDEX in "${!APPROVAL_CASE_NAMES[@]}"; do
    APPROVAL_CASE=${APPROVAL_CASE_NAMES[$APPROVAL_CASE_INDEX]}
    APPROVAL_STATE=${APPROVAL_CASE_VALUES[$APPROVAL_CASE_INDEX]}
    if OUTPUT=$(jq -n -L "$CONTROL_DIR" --argjson state "$APPROVAL_STATE" \
      --arg operation record-write --argjson data "$APPROVAL_DATA" \
      -f "$CONTROL_DIR/reducer.jq" 2>&1); then
      contract_failure "Malformed/stale replay approval was accepted: ${APPROVAL_CASE}"
    elif [[ $OUTPUT != *PROCESSOR_AUTHORITY_INVALID* ]]; then
      contract_failure "Malformed replay approval failed with the wrong refusal: ${APPROVAL_CASE}"
    fi
  done

  APPROVAL_NOT_CONSUMED=$(jq -c '.approvedOverwrites[0].consumedAt = null' \
    <<<"$APPROVAL_WRITTEN")
  if OUTPUT=$(jq -n -L "$CONTROL_DIR" --argjson state "$APPROVAL_NOT_CONSUMED" \
    --arg operation complete-tier --argjson data '{}' -f "$CONTROL_DIR/reducer.jq" 2>&1); then
    contract_failure 'Committed approval branch was accepted without consumption'
  elif [[ $OUTPUT != *WRITE_REPORT_MISSING* ]]; then
    contract_failure 'Unconsumed committed approval failed with the wrong refusal'
  fi
  APPROVAL_REUSE_STATE=$(jq -c '
    .pending = ["docs/r.mdx"] | .filesWritten = 0 |
    .provenance["docs/r.mdx"].writeStatus = "pending" |
    .provenance["docs/r.mdx"].writerReport = null
  ' <<<"$APPROVAL_WRITTEN")
  if OUTPUT=$(jq -n -L "$CONTROL_DIR" --argjson state "$APPROVAL_REUSE_STATE" \
    --arg operation record-write --argjson data "$APPROVAL_DATA" \
    -f "$CONTROL_DIR/reducer.jq" 2>&1); then
    contract_failure 'Consumed replay approval was reused'
  elif [[ $OUTPUT != *PROCESSOR_AUTHORITY_INVALID* ]]; then
    contract_failure 'Reused approval failed with the wrong refusal'
  fi

  NORMAL_WITH_APPROVAL=$(jq -n -L "$CONTROL_DIR" \
    --argjson state "$APPROVAL_PENDING_STATE" --arg operation record-write \
    --argjson data "$WRITE_DATA_VALID" -f "$CONTROL_DIR/reducer.jq") || true
  if [[ -z $NORMAL_WITH_APPROVAL ]] || ! jq -e \
    '.approvedOverwrites[0].consumedAt == null' <<<"$NORMAL_WITH_APPROVAL" >/dev/null; then
    contract_failure 'Normal start branch consumed an unrelated replay approval'
  fi

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
  PLAN_BASE=$(jq -c '.step = "write_tier_4"' <<<"$BASE_STATE")

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
  TRAILING_ROOT_PLAN=$(jq -c '.livePlan.docsRoot = "docs/"' <<<"$PLAN_BASE")
  DOT_TARGET_PLAN=$(jq -c '
    .livePlan.modules[0].files[0].crossLinks.concepts = ["./a.mdx"]
  ' <<<"$PLAN_BASE")
  NORMALIZATION_CASE_NAMES=(TRAILING_ROOT_PLAN DOT_TARGET_PLAN)
  NORMALIZATION_CASE_VALUES=("$TRAILING_ROOT_PLAN" "$DOT_TARGET_PLAN")
  for NORMALIZATION_CASE_INDEX in "${!NORMALIZATION_CASE_NAMES[@]}"; do
    NORMALIZATION_CASE=${NORMALIZATION_CASE_NAMES[$NORMALIZATION_CASE_INDEX]}
    NORMALIZATION_STATE=${NORMALIZATION_CASE_VALUES[$NORMALIZATION_CASE_INDEX]}
    if OUTPUT=$(jq -n -L "$CONTROL_DIR" --argjson state "$NORMALIZATION_STATE" \
      --arg operation write-dispatch --argjson data '{}' \
      -f "$CONTROL_DIR/reducer.jq" 2>&1); then
      contract_failure "Unnormalized live-plan metadata was accepted: ${NORMALIZATION_CASE}"
    elif [[ $OUTPUT != *PLAN_DRIFT_BLOCKED* ]]; then
      contract_failure "Unnormalized live-plan metadata failed with the wrong refusal: ${NORMALIZATION_CASE}"
    fi
  done
  VALID_CLOSED_CHAIN=$(jq -c --arg hash "$PLAN_C" --argjson first "$CLOSED_RECORD_AB" \
    --argjson second "$CLOSED_RECORD_BC" --arg scaffoldA "$SCAFFOLD_A" \
    --arg scaffoldB "$SCAFFOLD_B" --argjson livePlan "$SECOND_PLAN_BYTES" '
      .gapsResolved = [$first,$second] |
      .authorizedPlanHash = $hash | .livePlanHash = $hash |
      .livePlan = $livePlan |
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
  OMITTED_STORED_LINK=$(jq -c '
    .livePlan.modules[0].files[0].crossLinks.concepts = []
  ' <<<"$VALID_CLOSED_CHAIN")
  if OUTPUT=$(jq -n -L "$CONTROL_DIR" --argjson state "$OMITTED_STORED_LINK" \
    --arg operation write-dispatch --argjson data '{}' \
    -f "$CONTROL_DIR/reducer.jq" 2>&1); then
    contract_failure 'Live plan omitting a stored added link was accepted'
  elif [[ $OUTPUT != *PLAN_DRIFT_BLOCKED* ]]; then
    contract_failure 'Omitted stored added link failed with the wrong refusal'
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
  MISSING_LATER_PLAN_MUTATION=$(jq -c 'del(.gapsResolved[1].planMutation)' \
    <<<"$VALID_CLOSED_CHAIN")
  MISSING_LATER_GAP_PATHS=$(jq -c 'del(.gapsResolved[1].gapPaths)' \
    <<<"$VALID_CLOSED_CHAIN")
  HISTORY_CASE_NAMES=(TRUNCATED_HISTORY NO_REPORT_HISTORY BLANK_REASON_HISTORY
    CONFLICTING_HISTORY DUPLICATE_OPENED_HISTORY NO_CLOSED_AT_HISTORY
    DUPLICATE_REPORTER_HISTORY EMPTY_REQUEUED_HISTORY EMPTY_RESET_HISTORY
    RESET_WITHOUT_REPLAY_HISTORY WRONG_ADDED_ENTRY_HISTORY MISSING_ADDED_LINK_HISTORY
    MISSING_LATER_PLAN_MUTATION MISSING_LATER_GAP_PATHS)
  HISTORY_CASE_VALUES=("$TRUNCATED_HISTORY" "$NO_REPORT_HISTORY" "$BLANK_REASON_HISTORY"
    "$CONFLICTING_HISTORY" "$DUPLICATE_OPENED_HISTORY" "$NO_CLOSED_AT_HISTORY"
    "$DUPLICATE_REPORTER_HISTORY" "$EMPTY_REQUEUED_HISTORY" "$EMPTY_RESET_HISTORY"
    "$RESET_WITHOUT_REPLAY_HISTORY" "$WRONG_ADDED_ENTRY_HISTORY" "$MISSING_ADDED_LINK_HISTORY"
    "$MISSING_LATER_PLAN_MUTATION" "$MISSING_LATER_GAP_PATHS")
  for HISTORY_CASE_INDEX in "${!HISTORY_CASE_NAMES[@]}"; do
    HISTORY_CASE=${HISTORY_CASE_NAMES[$HISTORY_CASE_INDEX]}
    HISTORY=${HISTORY_CASE_VALUES[$HISTORY_CASE_INDEX]}
    printf '%s' "$HISTORY" >"$CONTROL_DIR/${HISTORY_CASE}.before"
    if OUTPUT=$(jq -n -L "$CONTROL_DIR" --argjson state "$HISTORY" \
      --arg operation write-dispatch --argjson data '{}' -f "$CONTROL_DIR/reducer.jq" 2>&1); then
      contract_failure "Malformed closed history was accepted: ${HISTORY_CASE}"
    elif [[ $OUTPUT != *GAP_CLOSURE_INVALID* ]]; then
      contract_failure "Malformed closed history failed for the wrong reason: ${HISTORY_CASE}"
    fi
    printf '%s' "$HISTORY" >"$CONTROL_DIR/${HISTORY_CASE}.after"
    if ! cmp -s "$CONTROL_DIR/${HISTORY_CASE}.before" "$CONTROL_DIR/${HISTORY_CASE}.after"; then
      contract_failure "Malformed closed history mutated while refusing: ${HISTORY_CASE}"
    fi
  done
  if [[ $FAILURES -eq $CONTROL_FAILURES_BEFORE ]]; then
    echo '✅ Complete ordered two-link history rejected reordering, skipped links, and malformed closures'
  fi

  CONTROL_FAILURES_BEFORE=$FAILURES
  DUPLICATE_CLOSED_GAP=$(jq -c '
    .gapsResolved[1].gapPaths[0].path = .gapsResolved[0].gapPaths[0].path
  ' <<<"$VALID_CLOSED_CHAIN")
  LIVE_REPEATED_GAP=$(jq -c --argjson live "$GAP_RECORD" '
    .gapsResolved = [.gapsResolved[0]] |
    .gapStatus = "enqueued" | .gapRecord = $live
  ' <<<"$VALID_CLOSED_CHAIN")
  GAP_LOOP_NAMES=(DUPLICATE_CLOSED_GAP LIVE_REPEATED_GAP)
  GAP_LOOP_VALUES=("$DUPLICATE_CLOSED_GAP" "$LIVE_REPEATED_GAP")
  for GAP_LOOP_INDEX in "${!GAP_LOOP_NAMES[@]}"; do
    GAP_LOOP_NAME=${GAP_LOOP_NAMES[$GAP_LOOP_INDEX]}
    GAP_LOOP_STATE=${GAP_LOOP_VALUES[$GAP_LOOP_INDEX]}
    printf '%s' "$GAP_LOOP_STATE" >"$CONTROL_DIR/${GAP_LOOP_NAME}.before"
    if OUTPUT=$(jq -n -L "$CONTROL_DIR" --argjson state "$GAP_LOOP_STATE" \
      --arg operation write-dispatch --argjson data '{}' \
      -f "$CONTROL_DIR/reducer.jq" 2>&1); then
      contract_failure "Repeated gap path was accepted: ${GAP_LOOP_NAME}"
    elif [[ $OUTPUT != *GAP_LOOP* ]]; then
      contract_failure "Repeated gap path failed with the wrong refusal: ${GAP_LOOP_NAME}"
    fi
    printf '%s' "$GAP_LOOP_STATE" >"$CONTROL_DIR/${GAP_LOOP_NAME}.after"
    if ! cmp -s "$CONTROL_DIR/${GAP_LOOP_NAME}.before" \
      "$CONTROL_DIR/${GAP_LOOP_NAME}.after"; then
      contract_failure "Repeated gap path mutated while refusing: ${GAP_LOOP_NAME}"
    fi
  done
  if [[ $FAILURES -eq $CONTROL_FAILURES_BEFORE ]]; then
    echo '✅ Closed/live repeated gap paths refused GAP_LOOP byte-identically'
  fi

  CONTROL_FAILURES_BEFORE=$FAILURES
  COMPLEX_CLOSURE_STATE=$(jq -c --arg root "$COMPLEX_PLAN_ROOT" \
    --arg final "$COMPLEX_PLAN_FINAL" --argjson livePlan "$COMPLEX_PLAN_BYTES" \
    --argjson closed "$COMPLEX_CLOSED_RECORD" --arg scaffold "$SCAFFOLD_A" '
      .planStateHash = $root | .approvedPlanHash = $root |
      .authorizedPlanHash = $final | .livePlanHash = $final | .livePlan = $livePlan |
      .candidateHash = null | .candidatePlan = null | .gapStatus = null |
      .gapPlanMutation = null | .gapRecord = null | .gapsResolved = [$closed] |
      .currentTier = 4 |
      .writeQueue = [
        "docs/r.mdx","docs/dep.mdx","docs/top.mdx","docs/nav.mdx",
        "docs/unrelated.mdx","docs/area/index.mdx","docs/area/gap.mdx"
      ] |
      .provenance = {
        "docs/r.mdx":{tier:4,writeStatus:"pending",scaffoldHash:$scaffold,
          writtenHash:null,writerReport:null},
        "docs/dep.mdx":{tier:3,writeStatus:"pending",scaffoldHash:$scaffold,
          writtenHash:null,writerReport:null},
        "docs/top.mdx":{tier:1,writeStatus:"pending",scaffoldHash:$scaffold,
          writtenHash:null,writerReport:null},
        "docs/nav.mdx":{tier:5,writeStatus:"pending",scaffoldHash:$scaffold,
          writtenHash:null,writerReport:null},
        "docs/unrelated.mdx":{tier:4,writeStatus:"pending",scaffoldHash:$scaffold,
          writtenHash:null,writerReport:null},
        "docs/area/index.mdx":{tier:6,writeStatus:"pending",scaffoldHash:$scaffold,
          writtenHash:null,writerReport:null},
        "docs/area/gap.mdx":{tier:2,writeStatus:"pending",scaffoldHash:$scaffold,
          writtenHash:null,writerReport:null}
      }
    ' <<<"$PLAN_BASE")
  if ! jq -n -L "$CONTROL_DIR" --argjson state "$COMPLEX_CLOSURE_STATE" \
    --arg operation write-dispatch --argjson data '{}' -f "$CONTROL_DIR/reducer.jq" \
    >/dev/null; then
    contract_failure 'Healthy transitive reverse-link and same-directory index closure was rejected'
  fi

  LIVE_SUCCESSOR_PLAN=$(jq -c '
    .modules[0].files[] |=
      if .path == "unrelated.mdx" then
        .crossLinks.concepts = ["area/future.mdx"]
      else . end |
    .shared.files += [{
      path:"area/future.mdx",type:"concept",tier:2,
      description:"Later live discovered concept",sources:["src/unrelated.ts"],
      crossLinks:{concepts:["r.mdx"],algorithms:[]},tags:["orders"]
    }]
  ' <<<"$COMPLEX_PLAN_BYTES")
  LIVE_SUCCESSOR_HASH=$(printf '%s' "$LIVE_SUCCESSOR_PLAN" | sha256sum | cut -d ' ' -f1)
  LIVE_SUCCESSOR_MUTATION=$(jq -cn --arg from "$COMPLEX_PLAN_FINAL" \
    --arg to "$LIVE_SUCCESSOR_HASH" --arg candidate "$CONTRACT_CANDIDATE_PATH" \
    --argjson plan "$LIVE_SUCCESSOR_PLAN" '{
      candidatePath:$candidate,fromPlanHash:$from,toPlanHash:$to,
      addedPlanEntries:[{
        outputPath:"docs/area/future.mdx",container:"shared",entry:$plan.shared.files[1]
      }],
      addedCrossLinks:[{
        reportedBy:"docs/unrelated.mdx",field:"concepts",target:"docs/area/future.mdx"
      }]
    }')
  LIVE_SUCCESSOR_RECORD=$(jq -cn --argjson mutation "$LIVE_SUCCESSOR_MUTATION" \
    --arg scaffold "$SCAFFOLD_B" '{
      status:"scaffolded",reports:[{reportedBy:"docs/unrelated.mdx",gaps:[{
        path:"docs/area/future.mdx",type:"concept",tier:2,
        reason:"Later transition needs a future area concept"
      }]}],gapPaths:[{path:"docs/area/future.mdx",type:"concept",tier:2}],
      expectedScaffold:{"docs/area/future.mdx":$scaffold},replayTier:2,
      requeued:["docs/unrelated.mdx"],resetTiers:[2,4],cleanedTiers:[],
      openedAt:"2026-08-01T00:03:00Z",planMutation:$mutation
    }')
  CLOSED_WITH_LIVE_SUCCESSOR=$(jq -c --arg hash "$LIVE_SUCCESSOR_HASH" \
    --argjson plan "$LIVE_SUCCESSOR_PLAN" --argjson mutation "$LIVE_SUCCESSOR_MUTATION" \
    --argjson record "$LIVE_SUCCESSOR_RECORD" --arg scaffold "$SCAFFOLD_B" '
      .authorizedPlanHash = $hash | .livePlanHash = $hash | .livePlan = $plan |
      .gapStatus = "scaffolded" | .gapPlanMutation = $mutation | .gapRecord = $record |
      .writeQueue += ["docs/area/future.mdx"] |
      .provenance["docs/area/future.mdx"] = {
        tier:2,writeStatus:"pending",scaffoldHash:$scaffold,
        writtenHash:null,writerReport:null
      }
    ' <<<"$COMPLEX_CLOSURE_STATE")
  if ! jq -n -L "$CONTROL_DIR" --argjson state "$CLOSED_WITH_LIVE_SUCCESSOR" \
    --arg operation write-dispatch --argjson data '{}' \
    -f "$CONTROL_DIR/reducer.jq" >/dev/null; then
    contract_failure 'Closed-history validation failed to remove a scaffolded live gap path from the older queue'
  fi

  TRUNCATED_CLOSURE=$(jq -c '
    .gapsResolved[0].requeued |= map(select(. != "docs/top.mdx")) |
    .gapsResolved[0].replayTier = 2 |
    .gapsResolved[0].resetTiers = [2,3,4,5,6] |
    .gapsResolved[0].cleanedTiers = [2,3,4,5,6]
  ' <<<"$COMPLEX_CLOSURE_STATE")
  INFLATED_CLOSURE=$(jq -c '
    .gapsResolved[0].requeued = [
      "docs/area/index.mdx","docs/dep.mdx","docs/nav.mdx","docs/r.mdx",
      "docs/top.mdx","docs/unrelated.mdx"
    ]
  ' <<<"$COMPLEX_CLOSURE_STATE")
  UNSORTED_CLOSURE=$(jq -c '.gapsResolved[0].requeued |= reverse' \
    <<<"$COMPLEX_CLOSURE_STATE")
  WRONG_REPLAY_TIER_CLOSURE=$(jq -c '.gapsResolved[0].replayTier = 2' \
    <<<"$COMPLEX_CLOSURE_STATE")
  CLOSURE_CASE_NAMES=(TRUNCATED_CLOSURE INFLATED_CLOSURE UNSORTED_CLOSURE
    WRONG_REPLAY_TIER_CLOSURE)
  CLOSURE_CASE_VALUES=("$TRUNCATED_CLOSURE" "$INFLATED_CLOSURE" "$UNSORTED_CLOSURE"
    "$WRONG_REPLAY_TIER_CLOSURE")
  for CLOSURE_CASE_INDEX in "${!CLOSURE_CASE_NAMES[@]}"; do
    CLOSURE_CASE=${CLOSURE_CASE_NAMES[$CLOSURE_CASE_INDEX]}
    CLOSURE_HISTORY=${CLOSURE_CASE_VALUES[$CLOSURE_CASE_INDEX]}
    printf '%s' "$CLOSURE_HISTORY" >"$CONTROL_DIR/${CLOSURE_CASE}.before"
    if OUTPUT=$(jq -n -L "$CONTROL_DIR" --argjson state "$CLOSURE_HISTORY" \
      --arg operation write-dispatch --argjson data '{}' \
      -f "$CONTROL_DIR/reducer.jq" 2>&1); then
      contract_failure "Inexact historical closure was accepted: ${CLOSURE_CASE}"
    elif [[ $OUTPUT != *GAP_CLOSURE_INVALID* ]]; then
      contract_failure "Inexact historical closure failed for the wrong reason: ${CLOSURE_CASE}"
    fi
    printf '%s' "$CLOSURE_HISTORY" >"$CONTROL_DIR/${CLOSURE_CASE}.after"
    if ! cmp -s "$CONTROL_DIR/${CLOSURE_CASE}.before" "$CONTROL_DIR/${CLOSURE_CASE}.after"; then
      contract_failure "Inexact historical closure mutated state while refusing: ${CLOSURE_CASE}"
    fi
  done
  if [[ $FAILURES -eq $CONTROL_FAILURES_BEFORE ]]; then
    echo '✅ Exact transitive/index closure rejected truncated, inflated, unsorted, and wrong-tier histories byte-identically'
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
      .filesWritten = 2 |
      .provenance["docs/s.mdx"] = {
        tier:4,writeStatus:"written",scaffoldHash:$from,writtenHash:$written,
        writerReport:{reportedBy:"docs/s.mdx",authorizedPlanHash:$plan,
          authorizedFromHash:$from,writtenHash:$written,gaps:[{
            path:"docs/a.mdx",type:"algorithm",tier:3,reason:"Conflicting reporter metadata"
          }]}
      } |
      .processorState.filesToProcess += ["docs/s.mdx"] |
      .processorState.pendingFiles = [] |
      .processorState.processedFiles = ["docs/r.mdx","docs/s.mdx"] |
      .processorState.recordWriteAuthorizations["docs/s.mdx"] = {
        normalHash:$from,replayApproval:null
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
  MISMATCHED_LIVE_INPUT=$(jq -c --arg live "$UNRELATED_PLAN_BYTES" \
    '.livePlanBytes = $live' <<<"$PLAN_INPUT")
  if OUTPUT=$(jq -n -L "$CONTROL_DIR" --argjson state "$AUTHORIZABLE_STATE" \
    --arg operation authorize-gap-plan --argjson data "$MISMATCHED_LIVE_INPUT" \
    -f "$CONTROL_DIR/reducer.jq" 2>&1); then
    contract_failure 'authorize-gap-plan accepted livePlanBytes that differed from state.livePlan'
  elif [[ $OUTPUT != *PLAN_DRIFT_BLOCKED* ]]; then
    contract_failure 'Mismatched livePlanBytes failed with the wrong refusal'
  fi
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
      ! jq -e --argjson candidate "$CANDIDATE_PLAN_BYTES" '
        .livePlan == $candidate and .candidatePlan == null
      ' <<<"$APPLIED" >/dev/null ||
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
    CRASH_TUPLE=$(jq -c --arg hash "$PLAN_B" --argjson livePlan "$CANDIDATE_PLAN_BYTES" '
      .livePlanHash = $hash | .livePlan = $livePlan |
      .candidateHash = null | .candidatePlan = null
    ' <<<"$AUTHORIZED")
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
    --arg scaffold "$SCAFFOLD_A" --argjson livePlan "$CANDIDATE_PLAN_BYTES" '
    .gapsResolved = [$closed] | .authorizedPlanHash = $hash | .livePlanHash = $hash |
    .livePlan = $livePlan |
    .writeQueue += ["docs/a.mdx"] |
    .provenance["docs/a.mdx"] = {
      tier:2,writeStatus:"pending",scaffoldHash:$scaffold,
      writtenHash:null,writerReport:null
    } |
    .processorState.authorizedPlanHash = $hash |
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

  HELPER_TRAILING_ROOT_BYTES=$(jq -c '.docsRoot = "docs/"' <<<"$LIVE_PLAN_BYTES")
  HELPER_DOT_TARGET_BYTES=$(jq -c '
    .modules[0].files[0].crossLinks.concepts = ["./a.mdx"]
  ' <<<"$LIVE_PLAN_BYTES")
  HELPER_NORMALIZATION_NAMES=(HELPER_TRAILING_ROOT_BYTES HELPER_DOT_TARGET_BYTES)
  HELPER_NORMALIZATION_VALUES=("$HELPER_TRAILING_ROOT_BYTES" "$HELPER_DOT_TARGET_BYTES")
  for HELPER_NORMALIZATION_INDEX in "${!HELPER_NORMALIZATION_NAMES[@]}"; do
    HELPER_NORMALIZATION_NAME=${HELPER_NORMALIZATION_NAMES[$HELPER_NORMALIZATION_INDEX]}
    HELPER_NORMALIZATION_BYTES=${HELPER_NORMALIZATION_VALUES[$HELPER_NORMALIZATION_INDEX]}
    HELPER_NORMALIZATION_HASH=$(printf '%s' "$HELPER_NORMALIZATION_BYTES" | \
      sha256sum | cut -d ' ' -f1)
    jq -c --arg hash "$HELPER_NORMALIZATION_HASH" '.planHash = $hash' \
      <<<"$AUTH_PLAN_STATE" >"$AUTH_PLAN_STATE_FILE"
    jq -c --arg hash "$HELPER_NORMALIZATION_HASH" '.authorizedPlanHash = $hash' \
      <<<"$AUTH_WRITE_STATE" >"$AUTH_WRITE_STATE_FILE"
    printf '%s' "$HELPER_NORMALIZATION_BYTES" >"$AUTH_PLAN_FILE"
    if OUTPUT=$(assert_plan_authority "$HELPER_NORMALIZATION_HASH" \
      "$AUTH_PLAN_STATE_FILE" "$AUTH_WRITE_STATE_FILE" "$AUTH_PLAN_FILE" \
      "$AUTH_CANDIDATE_FILE" 2>&1); then
      contract_failure "Direct authority helper accepted unnormalized plan metadata: ${HELPER_NORMALIZATION_NAME}"
    elif [[ $OUTPUT != *PLAN_DRIFT_BLOCKED* ]]; then
      contract_failure "Direct authority helper reported unnormalized plan metadata with the wrong refusal: ${HELPER_NORMALIZATION_NAME}"
    fi
  done
  printf '%s\n' "$AUTH_PLAN_STATE" >"$AUTH_PLAN_STATE_FILE"
  printf '%s\n' "$AUTH_WRITE_STATE" >"$AUTH_WRITE_STATE_FILE"
  printf '%s' "$LIVE_PLAN_BYTES" >"$AUTH_PLAN_FILE"

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
  HELPER_MISSING_LATER_PLAN_MUTATION=$(jq -c 'del(.gapsResolved[1].planMutation)' \
    <<<"$CHAIN_WRITE_STATE")
  HELPER_MISSING_LATER_GAP_PATHS=$(jq -c 'del(.gapsResolved[1].gapPaths)' \
    <<<"$CHAIN_WRITE_STATE")
  HELPER_CASE_NAMES=(HELPER_TRUNCATED HELPER_DUPLICATE_REPORTER HELPER_EMPTY_REQUEUED
    HELPER_EMPTY_RESET HELPER_RESET_WITHOUT_REPLAY HELPER_WRONG_ADDED_ENTRY
    HELPER_WRONG_ADDED_DESCRIPTION HELPER_MISSING_ADDED_LINK
    HELPER_MISSING_LATER_PLAN_MUTATION HELPER_MISSING_LATER_GAP_PATHS)
  HELPER_CASE_VALUES=("$HELPER_TRUNCATED" "$HELPER_DUPLICATE_REPORTER" "$HELPER_EMPTY_REQUEUED"
    "$HELPER_EMPTY_RESET" "$HELPER_RESET_WITHOUT_REPLAY" "$HELPER_WRONG_ADDED_ENTRY"
    "$HELPER_WRONG_ADDED_DESCRIPTION" "$HELPER_MISSING_ADDED_LINK"
    "$HELPER_MISSING_LATER_PLAN_MUTATION" "$HELPER_MISSING_LATER_GAP_PATHS")
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

  HELPER_DUPLICATE_GAP=$(jq -c '
    .gapsResolved[1].gapPaths[0].path = .gapsResolved[0].gapPaths[0].path
  ' <<<"$CHAIN_WRITE_STATE")
  printf '%s\n' "$HELPER_DUPLICATE_GAP" >"$AUTH_WRITE_STATE_FILE"
  cp "$AUTH_WRITE_STATE_FILE" "$CONTROL_DIR/helper-duplicate-gap.before"
  if OUTPUT=$(assert_plan_authority "$PLAN_C" "$AUTH_PLAN_STATE_FILE" \
    "$AUTH_WRITE_STATE_FILE" "$AUTH_PLAN_FILE" "$AUTH_CANDIDATE_FILE" 2>&1); then
    contract_failure 'Direct authority helper accepted a repeated closed gap path'
  elif [[ $OUTPUT != *GAP_LOOP* ]]; then
    contract_failure 'Direct authority helper reported a repeated gap with the wrong refusal'
  elif ! cmp -s "$AUTH_WRITE_STATE_FILE" "$CONTROL_DIR/helper-duplicate-gap.before"; then
    contract_failure 'Direct authority helper mutated repeated-gap history while refusing'
  fi
  printf '%s\n' "$CHAIN_WRITE_STATE" >"$AUTH_WRITE_STATE_FILE"

  COMPLEX_AUTH_PLAN_STATE=$(jq -c --arg hash "$COMPLEX_PLAN_ROOT" \
    '.planHash = $hash' <<<"$AUTH_PLAN_STATE")
  COMPLEX_AUTH_WRITE_STATE=$(jq -c --arg hash "$COMPLEX_PLAN_FINAL" \
    --argjson closed "$COMPLEX_CLOSED_RECORD" --arg scaffold "$SCAFFOLD_A" '
      .step = "write_tier_1" | .authorizedPlanHash = $hash | .currentTier = 1 |
      .tiersCompleted = [] | .filesWritten = 0 | .filesTotal = 7 |
      .writeQueue = [
        "docs/r.mdx","docs/dep.mdx","docs/top.mdx","docs/nav.mdx",
        "docs/unrelated.mdx","docs/area/index.mdx","docs/area/gap.mdx"
      ] |
      .provenance = {
        "docs/r.mdx":{origin:"planned",scaffoldHash:$scaffold,
          scaffoldedAt:"2026-08-01T00:00:00Z",tier:4,writeStatus:"pending",
          writtenHash:null,writerReport:null},
        "docs/dep.mdx":{origin:"planned",scaffoldHash:$scaffold,
          scaffoldedAt:"2026-08-01T00:00:00Z",tier:3,writeStatus:"pending",
          writtenHash:null,writerReport:null},
        "docs/top.mdx":{origin:"planned",scaffoldHash:$scaffold,
          scaffoldedAt:"2026-08-01T00:00:00Z",tier:1,writeStatus:"pending",
          writtenHash:null,writerReport:null},
        "docs/nav.mdx":{origin:"planned",scaffoldHash:$scaffold,
          scaffoldedAt:"2026-08-01T00:00:00Z",tier:5,writeStatus:"pending",
          writtenHash:null,writerReport:null},
        "docs/unrelated.mdx":{origin:"planned",scaffoldHash:$scaffold,
          scaffoldedAt:"2026-08-01T00:00:00Z",tier:4,writeStatus:"pending",
          writtenHash:null,writerReport:null},
        "docs/area/index.mdx":{origin:"planned",scaffoldHash:$scaffold,
          scaffoldedAt:"2026-08-01T00:00:00Z",tier:6,writeStatus:"pending",
          writtenHash:null,writerReport:null},
        "docs/area/gap.mdx":{origin:"new",scaffoldHash:$scaffold,
          scaffoldedAt:"2026-08-01T00:02:00Z",tier:2,writeStatus:"pending",
          writtenHash:null,writerReport:null}
      } | .gapsResolved = [$closed]
    ' <<<"$AUTH_WRITE_STATE")
  printf '%s\n' "$COMPLEX_AUTH_PLAN_STATE" >"$AUTH_PLAN_STATE_FILE"
  printf '%s\n' "$COMPLEX_AUTH_WRITE_STATE" >"$AUTH_WRITE_STATE_FILE"
  printf '%s' "$COMPLEX_PLAN_BYTES" >"$AUTH_PLAN_FILE"
  if ! assert_plan_authority "$COMPLEX_PLAN_FINAL" "$AUTH_PLAN_STATE_FILE" \
    "$AUTH_WRITE_STATE_FILE" "$AUTH_PLAN_FILE" "$AUTH_CANDIDATE_FILE"; then
    contract_failure 'Direct authority helper rejected healthy transitive/index closure'
  fi

  HELPER_TRUNCATED_CLOSURE=$(jq -c '
    .gapsResolved[0].requeued |= map(select(. != "docs/top.mdx")) |
    .gapsResolved[0].replayTier = 2 |
    .gapsResolved[0].resetTiers = [2,3,4,5,6] |
    .gapsResolved[0].cleanedTiers = [2,3,4,5,6]
  ' <<<"$COMPLEX_AUTH_WRITE_STATE")
  HELPER_INFLATED_CLOSURE=$(jq -c '
    .gapsResolved[0].requeued = [
      "docs/area/index.mdx","docs/dep.mdx","docs/nav.mdx","docs/r.mdx",
      "docs/top.mdx","docs/unrelated.mdx"
    ]
  ' <<<"$COMPLEX_AUTH_WRITE_STATE")
  HELPER_UNSORTED_CLOSURE=$(jq -c '.gapsResolved[0].requeued |= reverse' \
    <<<"$COMPLEX_AUTH_WRITE_STATE")
  HELPER_WRONG_REPLAY_TIER=$(jq -c '.gapsResolved[0].replayTier = 2' \
    <<<"$COMPLEX_AUTH_WRITE_STATE")
  HELPER_CLOSURE_CASE_NAMES=(HELPER_TRUNCATED_CLOSURE HELPER_INFLATED_CLOSURE
    HELPER_UNSORTED_CLOSURE HELPER_WRONG_REPLAY_TIER)
  HELPER_CLOSURE_CASE_VALUES=("$HELPER_TRUNCATED_CLOSURE" "$HELPER_INFLATED_CLOSURE"
    "$HELPER_UNSORTED_CLOSURE" "$HELPER_WRONG_REPLAY_TIER")
  for HELPER_CLOSURE_CASE_INDEX in "${!HELPER_CLOSURE_CASE_NAMES[@]}"; do
    HELPER_CLOSURE_CASE=${HELPER_CLOSURE_CASE_NAMES[$HELPER_CLOSURE_CASE_INDEX]}
    HELPER_CLOSURE_HISTORY=${HELPER_CLOSURE_CASE_VALUES[$HELPER_CLOSURE_CASE_INDEX]}
    printf '%s\n' "$HELPER_CLOSURE_HISTORY" >"$AUTH_WRITE_STATE_FILE"
    cp "$AUTH_WRITE_STATE_FILE" "$CONTROL_DIR/${HELPER_CLOSURE_CASE}.before"
    if OUTPUT=$(assert_plan_authority "$COMPLEX_PLAN_FINAL" "$AUTH_PLAN_STATE_FILE" \
      "$AUTH_WRITE_STATE_FILE" "$AUTH_PLAN_FILE" "$AUTH_CANDIDATE_FILE" 2>&1); then
      contract_failure "Direct authority helper accepted inexact closure: ${HELPER_CLOSURE_CASE}"
    elif [[ $OUTPUT != *GAP_CLOSURE_INVALID* ]]; then
      contract_failure "Direct authority helper reported inexact closure with the wrong refusal: ${HELPER_CLOSURE_CASE}"
    elif ! cmp -s "$AUTH_WRITE_STATE_FILE" "$CONTROL_DIR/${HELPER_CLOSURE_CASE}.before"; then
      contract_failure "Direct authority helper mutated inexact closure while refusing: ${HELPER_CLOSURE_CASE}"
    fi
  done
  printf '%s\n' "$AUTH_PLAN_STATE" >"$AUTH_PLAN_STATE_FILE"
  printf '%s\n' "$AUTH_WRITE_STATE" >"$AUTH_WRITE_STATE_FILE"
  printf '%s' "$LIVE_PLAN_BYTES" >"$AUTH_PLAN_FILE"
  if [[ $FAILURES -eq $CONTROL_FAILURES_BEFORE ]]; then
    echo '✅ Direct authority helper enforced live bytes, complete chain identity, and exact transitive/index closure'
  fi

  CONTROL_FAILURES_BEFORE=$FAILURES
  PROCESSOR_REPO="$CONTROL_DIR/processor-repo"
  git init -q "$PROCESSOR_REPO"
  mkdir -p "$PROCESSOR_REPO/.contributor-docs" "$PROCESSOR_REPO/docs"
  PROCESSOR_PLAN_STATE="$PROCESSOR_REPO/.contributor-docs/plan-state.json"
  PROCESSOR_TASK_STATE="$PROCESSOR_REPO/.contributor-docs/task-state.json"
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
  printf '%s\n' '{"docsRoot":"docs"}' >"$PROCESSOR_TASK_STATE"
  printf '%s\n' "$PROCESSOR_PENDING_WRITE" >"$PROCESSOR_WRITE_STATE"
  printf '%s' "$LIVE_PLAN_BYTES" >"$PROCESSOR_PLAN"
  printf '%s' "$FILE_BYTES" >"$PROCESSOR_REPO/docs/r.mdx"
  if ! printf '%s\n' 'docs/r.mdx' | (
    cd "$PROCESSOR_REPO" && bash "$CD_ROOT/scripts/init-state.sh" \
      .contributor-docs/write-tier-4/state.json '["src/r.ts"]' 1 out \
      --plan-hash "$PLAN_A"
  ) >/dev/null; then
    contract_failure 'Healthy processor initialization was refused'
  elif ! jq -e --arg hash "$PLAN_A" --arg normal "$FROM_HASH" '
    .authorizedPlanHash == $hash and .pendingFiles == ["docs/r.mdx"] and
    .recordWriteAuthorizations == {
      "docs/r.mdx":{normalHash:$normal,replayApproval:null}
    }
  ' "$PROCESSOR_STATE" >/dev/null; then
    contract_failure 'Processor initialization did not persist its exact authority snapshot and queue'
  fi

  PROCESSOR_REPLAY_WRITE=$(jq -c --arg retained "$RETAINED_HASH" '
    .provenance["docs/r.mdx"].writtenHash = $retained
  ' <<<"$PROCESSOR_PENDING_WRITE")
  printf '%s\n' "$PROCESSOR_REPLAY_WRITE" >"$PROCESSOR_WRITE_STATE"
  if ! printf '%s\n' 'docs/r.mdx' | (
    cd "$PROCESSOR_REPO" && bash "$CD_ROOT/scripts/init-state.sh" \
      .contributor-docs/write-tier-4/state.json '["src/r.ts"]' 1 out \
      --plan-hash "$PLAN_A"
  ) >/dev/null || ! jq -e --arg retained "$RETAINED_HASH" '
    .recordWriteAuthorizations["docs/r.mdx"] == {
      normalHash:$retained,replayApproval:null
    }
  ' "$PROCESSOR_STATE" >/dev/null; then
    contract_failure 'Replay processor initialization did not retain writtenHash as normal authority'
  fi

  PROCESSOR_APPROVAL_WRITE=$(jq -c --arg retained "$RETAINED_HASH" \
    --arg approved "$APPROVED_HASH" '
      .provenance["docs/r.mdx"].writtenHash = $retained |
      .approvedOverwrites = [{
        path:"docs/r.mdx",approvedHash:$approved,purpose:"writer-replay",
        approvedAt:"2026-08-01T00:03:00Z",consumedAt:null
      }]
    ' <<<"$PROCESSOR_PENDING_WRITE")
  printf '%s\n' "$PROCESSOR_APPROVAL_WRITE" >"$PROCESSOR_WRITE_STATE"
  if ! printf '%s\n' 'docs/r.mdx' | (
    cd "$PROCESSOR_REPO" && bash "$CD_ROOT/scripts/init-state.sh" \
      .contributor-docs/write-tier-4/state.json '["src/r.ts"]' 1 out \
      --plan-hash "$PLAN_A"
  ) >/dev/null || ! jq -e --arg retained "$RETAINED_HASH" --arg approved "$APPROVED_HASH" '
    .recordWriteAuthorizations["docs/r.mdx"] == {
      normalHash:$retained,replayApproval:{ledgerIndex:0,approvedHash:$approved}
    }
  ' "$PROCESSOR_STATE" >/dev/null; then
    contract_failure 'Processor initialization did not persist the exact approval ledger index/hash'
  fi

  PROCESSOR_FACT_STATE="$PROCESSOR_REPO/.contributor-docs/fact-check/state.json"
  if ! printf '%s\n' 'docs/r.mdx' | (
    cd "$PROCESSOR_REPO" && bash "$CD_ROOT/scripts/init-state.sh" \
      .contributor-docs/fact-check/state.json '["src/r.ts"]' 1 \
      .contributor-docs/fact-check/findings --plan-hash "$PLAN_A"
  ) >/dev/null || ! jq -e '.recordWriteAuthorizations == null' \
    "$PROCESSOR_FACT_STATE" >/dev/null; then
    contract_failure 'Fact-check processor initialization did not persist null write authorization'
  fi

  printf '%s\n' "$PROCESSOR_PENDING_WRITE" >"$PROCESSOR_WRITE_STATE"
  if ! printf '%s\n' 'docs/r.mdx' | (
    cd "$PROCESSOR_REPO" && bash "$CD_ROOT/scripts/init-state.sh" \
      .contributor-docs/write-tier-4/state.json '["src/r.ts"]' 1 out \
      --plan-hash "$PLAN_A"
  ) >/dev/null; then
    contract_failure 'Processor fixture could not restore the first-write authorization snapshot'
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
    contract_failure "Processor initialization reported live-plan drift with the wrong refusal: ${OUTPUT}"
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
    contract_failure "Processor completion reported written-byte drift with the wrong refusal: ${OUTPUT}"
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
    contract_failure "Processor completion reported a missing writer report with the wrong refusal: ${OUTPUT}"
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
    contract_failure "Malformed processor writer report failed with the wrong refusal: ${OUTPUT}"
  elif ! cmp -s "$PROCESSOR_STATE" "$CONTROL_DIR/mark-malformed-report.before"; then
    contract_failure 'Processor completion changed state while refusing a malformed report'
  fi

  printf '%s\n' "$AUTH_WRITE_STATE" >"$PROCESSOR_WRITE_STATE"
  cp "$PROCESSOR_STATE" "$CONTROL_DIR/processor-current-format.json"
  jq 'del(.recordWriteAuthorizations)' "$PROCESSOR_STATE" >"$CONTROL_DIR/processor-legacy.json"
  cp "$CONTROL_DIR/processor-legacy.json" "$PROCESSOR_STATE"
  if OUTPUT=$(
    cd "$PROCESSOR_REPO" && bash "$CD_ROOT/scripts/mark-done.sh" \
      .contributor-docs/write-tier-4/state.json docs/r.mdx --plan-hash "$PLAN_A" 2>&1
  ); then
    contract_failure 'Legacy processor missing recordWriteAuthorizations was accepted'
  elif [[ $OUTPUT != *PROCESSOR_AUTHORITY_INVALID* ]]; then
    contract_failure 'Legacy processor format failed with the wrong refusal'
  fi
  cp "$CONTROL_DIR/processor-current-format.json" "$PROCESSOR_STATE"

  mkdir -p "$PROCESSOR_REPO/outside"
  printf '%s' "$FILE_BYTES" >"$PROCESSOR_REPO/outside/escape.mdx"
  ln -s ../outside "$PROCESSOR_REPO/docs/escape-link"
  ESCAPE_PATH=docs/escape-link/escape.mdx
  ESCAPE_REPORT=$(jq -cn --arg path "$ESCAPE_PATH" --arg plan "$PLAN_A" \
    --arg from "$FROM_HASH" --arg written "$FILE_HASH" '{
      reportedBy:$path,authorizedPlanHash:$plan,authorizedFromHash:$from,
      writtenHash:$written,gaps:[]
    }')
  ESCAPE_WRITE_STATE=$(jq -c --arg path "$ESCAPE_PATH" --arg scaffold "$FROM_HASH" \
    --arg written "$FILE_HASH" --argjson report "$ESCAPE_REPORT" '
      .writeQueue = [$path] | .filesWritten = 1 | .filesTotal = 1 |
      .provenance = {($path):{
        origin:"new",scaffoldHash:$scaffold,scaffoldedAt:"2026-08-01T00:00:00Z",
        tier:4,writeStatus:"written",writtenHash:$written,writerReport:$report
      }}
    ' <<<"$AUTH_WRITE_STATE")
  ESCAPE_PROCESSOR_STATE=$(jq -c --arg path "$ESCAPE_PATH" --arg from "$FROM_HASH" '
    .filesToProcess = [$path] | .pendingFiles = [$path] | .processedFiles = [] |
    .recordWriteAuthorizations = {($path):{normalHash:$from,replayApproval:null}}
  ' "$PROCESSOR_STATE")
  printf '%s\n' "$ESCAPE_WRITE_STATE" >"$PROCESSOR_WRITE_STATE"
  printf '%s\n' "$ESCAPE_PROCESSOR_STATE" >"$PROCESSOR_STATE"
  cp "$PROCESSOR_STATE" "$CONTROL_DIR/symlink-escape.before"
  if OUTPUT=$(
    cd "$PROCESSOR_REPO" && bash "$CD_ROOT/scripts/mark-done.sh" \
      .contributor-docs/write-tier-4/state.json "$ESCAPE_PATH" --plan-hash "$PLAN_A" 2>&1
  ); then
    contract_failure 'Processor completion accepted an existing-parent symlink escape'
  elif [[ $OUTPUT != *GAP_REPORT_SET_INVALID* ]]; then
    contract_failure 'Symlink-escaped reporter failed with the wrong refusal'
  elif ! cmp -s "$PROCESSOR_STATE" "$CONTROL_DIR/symlink-escape.before"; then
    contract_failure 'Symlink-escaped reporter mutated processor state while refusing'
  fi
  printf '%s\n' "$AUTH_WRITE_STATE" >"$PROCESSOR_WRITE_STATE"
  cp "$CONTROL_DIR/processor-current-format.json" "$PROCESSOR_STATE"

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

  CONTROL_FAILURES_BEFORE=$FAILURES
  BARRIER_ROOT="$CONTROL_DIR/authority-barriers"
  mkdir -p "$BARRIER_ROOT"

  # init-state: a compliant concurrent initializer must fail fast while the first
  # owns the lock, without changing authority or processor state.
  printf '%s\n' "$PROCESSOR_PENDING_WRITE" >"$PROCESSOR_WRITE_STATE"
  if ! printf '%s\n' 'docs/r.mdx' | (
    cd "$PROCESSOR_REPO" && bash "$CD_ROOT/scripts/init-state.sh" \
      .contributor-docs/write-tier-4/state.json '["src/r.ts"]' 1 out \
      --plan-hash "$PLAN_A"
  ) >/dev/null; then
    contract_failure 'Could not prepare init contention fixture'
  fi
  INIT_READY="$BARRIER_ROOT/init-contention.ready"
  INIT_RELEASE="$BARRIER_ROOT/init-contention.release"
  INIT_OUTPUT="$BARRIER_ROOT/init-contention.output"
  mkfifo "$INIT_RELEASE"
  INIT_MANIFEST_BEFORE=$(processor_fixture_manifest "$PROCESSOR_REPO" \
    "$PROCESSOR_STATE" docs/r.mdx)
  (
    cd "$PROCESSOR_REPO" && printf '%s\n' 'docs/r.mdx' | \
      env CONTRIBUTOR_DOCS_CONTRACT_TEST=1 \
        CONTRIBUTOR_DOCS_TEST_BARRIER_POINT=init-before-cas \
        CONTRIBUTOR_DOCS_TEST_ROOT="$BARRIER_ROOT" \
        CONTRIBUTOR_DOCS_TEST_READY_FILE="$INIT_READY" \
        CONTRIBUTOR_DOCS_TEST_RELEASE_FIFO="$INIT_RELEASE" \
        bash "$CD_ROOT/scripts/init-state.sh" \
          .contributor-docs/write-tier-4/state.json '["src/r.ts"]' 1 out \
          --plan-hash "$PLAN_A"
  ) >"$INIT_OUTPUT" 2>&1 &
  INIT_PID=$!
  if ! wait_for_contract_barrier "$INIT_READY"; then
    contract_failure 'init-state contention barrier was not reached'
    kill "$INIT_PID" 2>/dev/null || true
  else
    if OUTPUT=$(printf '%s\n' 'docs/r.mdx' | (
      cd "$PROCESSOR_REPO" && bash "$CD_ROOT/scripts/init-state.sh" \
        .contributor-docs/write-tier-4/state.json '["src/r.ts"]' 1 out \
        --plan-hash "$PLAN_A"
    ) 2>&1); then
      contract_failure 'Concurrent compliant initializer did not fail fast'
    elif [[ $OUTPUT != *AUTHORITY_BUSY* ]]; then
      contract_failure 'Concurrent initializer failed with the wrong refusal'
    fi
    INIT_MANIFEST_BUSY=$(processor_fixture_manifest "$PROCESSOR_REPO" \
      "$PROCESSOR_STATE" docs/r.mdx)
    if [[ $INIT_MANIFEST_BUSY != "$INIT_MANIFEST_BEFORE" ]]; then
      contract_failure 'Busy initializer changed authority or processor state'
    fi
    printf '%s\n' release >"$INIT_RELEASE"
    if ! wait "$INIT_PID"; then
      contract_failure 'Lock-owning initializer failed after contention release'
    fi
  fi

  # init-state: mutate canonical authority only after the last semantic check.
  INIT_RAW_READY="$BARRIER_ROOT/init-raw.ready"
  INIT_RAW_RELEASE="$BARRIER_ROOT/init-raw.release"
  INIT_RAW_OUTPUT="$BARRIER_ROOT/init-raw.output"
  mkfifo "$INIT_RAW_RELEASE"
  printf '%s\n' "$PROCESSOR_PENDING_WRITE" >"$PROCESSOR_WRITE_STATE"
  INIT_RAW_PROCESSOR_BEFORE=$(authority_snapshot "$PROCESSOR_STATE")
  (
    cd "$PROCESSOR_REPO" && printf '%s\n' 'docs/r.mdx' | \
      env CONTRIBUTOR_DOCS_CONTRACT_TEST=1 \
        CONTRIBUTOR_DOCS_TEST_BARRIER_POINT=init-before-cas \
        CONTRIBUTOR_DOCS_TEST_ROOT="$BARRIER_ROOT" \
        CONTRIBUTOR_DOCS_TEST_READY_FILE="$INIT_RAW_READY" \
        CONTRIBUTOR_DOCS_TEST_RELEASE_FIFO="$INIT_RAW_RELEASE" \
        bash "$CD_ROOT/scripts/init-state.sh" \
          .contributor-docs/write-tier-4/state.json '["src/r.ts"]' 1 out \
          --plan-hash "$PLAN_A"
  ) >"$INIT_RAW_OUTPUT" 2>&1 &
  INIT_RAW_PID=$!
  if ! wait_for_contract_barrier "$INIT_RAW_READY"; then
    contract_failure 'init-state raw-mutation barrier was not reached'
    kill "$INIT_RAW_PID" 2>/dev/null || true
  else
    RAW_WRITE_TEMP=$(mktemp "${PROCESSOR_WRITE_STATE}.raw.XXXXXX")
    jq '.blockedCollisions = [{path:"docs/r.mdx"}]' \
      "$PROCESSOR_WRITE_STATE" >"$RAW_WRITE_TEMP"
    mv "$RAW_WRITE_TEMP" "$PROCESSOR_WRITE_STATE"
    printf '%s\n' release >"$INIT_RAW_RELEASE"
    if wait "$INIT_RAW_PID"; then
      contract_failure 'init-state CAS accepted a raw final-interval authority mutation'
    elif ! rg -qF PROCESSOR_AUTHORITY_INVALID "$INIT_RAW_OUTPUT"; then
      contract_failure 'init-state raw mutation failed with the wrong refusal'
    fi
  fi
  printf '%s\n' "$PROCESSOR_PENDING_WRITE" >"$PROCESSOR_WRITE_STATE"
  if [[ $(authority_snapshot "$PROCESSOR_STATE") != "$INIT_RAW_PROCESSOR_BEFORE" ]]; then
    contract_failure 'init-state CAS failure replaced processor state'
  fi
  if find "$(dirname "$PROCESSOR_STATE")" -maxdepth 1 -type f \
    -name 'state.json.??????' -print -quit | rg -q .; then
    contract_failure 'init-state ordinary CAS failure left a temporary state file'
  fi

  # mark-done: prove lock contention, then prove its own final CAS detects a raw
  # writer-report mutation before processor replacement.
  if ! printf '%s\n' 'docs/r.mdx' | (
    cd "$PROCESSOR_REPO" && bash "$CD_ROOT/scripts/init-state.sh" \
      .contributor-docs/write-tier-4/state.json '["src/r.ts"]' 1 out \
      --plan-hash "$PLAN_A"
  ) >/dev/null; then
    contract_failure 'Could not prepare mark contention fixture'
  fi
  printf '%s\n' "$AUTH_WRITE_STATE" >"$PROCESSOR_WRITE_STATE"
  MARK_READY="$BARRIER_ROOT/mark-contention.ready"
  MARK_RELEASE="$BARRIER_ROOT/mark-contention.release"
  MARK_OUTPUT="$BARRIER_ROOT/mark-contention.output"
  mkfifo "$MARK_RELEASE"
  MARK_MANIFEST_BEFORE=$(processor_fixture_manifest "$PROCESSOR_REPO" \
    "$PROCESSOR_STATE" docs/r.mdx)
  (
    cd "$PROCESSOR_REPO" && env CONTRIBUTOR_DOCS_CONTRACT_TEST=1 \
      CONTRIBUTOR_DOCS_TEST_BARRIER_POINT=mark-before-cas \
      CONTRIBUTOR_DOCS_TEST_ROOT="$BARRIER_ROOT" \
      CONTRIBUTOR_DOCS_TEST_READY_FILE="$MARK_READY" \
      CONTRIBUTOR_DOCS_TEST_RELEASE_FIFO="$MARK_RELEASE" \
      bash "$CD_ROOT/scripts/mark-done.sh" \
        .contributor-docs/write-tier-4/state.json docs/r.mdx --plan-hash "$PLAN_A"
  ) >"$MARK_OUTPUT" 2>&1 &
  MARK_PID=$!
  if ! wait_for_contract_barrier "$MARK_READY"; then
    contract_failure 'mark-done contention barrier was not reached'
    kill "$MARK_PID" 2>/dev/null || true
  else
    if OUTPUT=$(
      cd "$PROCESSOR_REPO" && bash "$CD_ROOT/scripts/mark-done.sh" \
        .contributor-docs/write-tier-4/state.json docs/r.mdx --plan-hash "$PLAN_A" 2>&1
    ); then
      contract_failure 'Concurrent compliant mark did not fail fast'
    elif [[ $OUTPUT != *AUTHORITY_BUSY* ]]; then
      contract_failure 'Concurrent mark failed with the wrong refusal'
    fi
    MARK_MANIFEST_BUSY=$(processor_fixture_manifest "$PROCESSOR_REPO" \
      "$PROCESSOR_STATE" docs/r.mdx)
    if [[ $MARK_MANIFEST_BUSY != "$MARK_MANIFEST_BEFORE" ]]; then
      contract_failure 'Busy mark changed authority or processor state'
    fi
    printf '%s\n' release >"$MARK_RELEASE"
    if ! wait "$MARK_PID"; then
      contract_failure 'Lock-owning mark failed after contention release'
    fi
  fi

  printf '%s\n' "$PROCESSOR_PENDING_WRITE" >"$PROCESSOR_WRITE_STATE"
  if ! printf '%s\n' 'docs/r.mdx' | (
    cd "$PROCESSOR_REPO" && bash "$CD_ROOT/scripts/init-state.sh" \
      .contributor-docs/write-tier-4/state.json '["src/r.ts"]' 1 out \
      --plan-hash "$PLAN_A"
  ) >/dev/null; then
    contract_failure 'Could not prepare mark raw-mutation fixture'
  fi
  printf '%s\n' "$AUTH_WRITE_STATE" >"$PROCESSOR_WRITE_STATE"
  MARK_RAW_READY="$BARRIER_ROOT/mark-raw.ready"
  MARK_RAW_RELEASE="$BARRIER_ROOT/mark-raw.release"
  MARK_RAW_OUTPUT="$BARRIER_ROOT/mark-raw.output"
  mkfifo "$MARK_RAW_RELEASE"
  MARK_RAW_PROCESSOR_BEFORE=$(authority_snapshot "$PROCESSOR_STATE")
  (
    cd "$PROCESSOR_REPO" && env CONTRIBUTOR_DOCS_CONTRACT_TEST=1 \
      CONTRIBUTOR_DOCS_TEST_BARRIER_POINT=mark-before-cas \
      CONTRIBUTOR_DOCS_TEST_ROOT="$BARRIER_ROOT" \
      CONTRIBUTOR_DOCS_TEST_READY_FILE="$MARK_RAW_READY" \
      CONTRIBUTOR_DOCS_TEST_RELEASE_FIFO="$MARK_RAW_RELEASE" \
      bash "$CD_ROOT/scripts/mark-done.sh" \
        .contributor-docs/write-tier-4/state.json docs/r.mdx --plan-hash "$PLAN_A"
  ) >"$MARK_RAW_OUTPUT" 2>&1 &
  MARK_RAW_PID=$!
  if ! wait_for_contract_barrier "$MARK_RAW_READY"; then
    contract_failure 'mark-done raw-mutation barrier was not reached'
    kill "$MARK_RAW_PID" 2>/dev/null || true
  else
    RAW_MARK_TEMP=$(mktemp "${PROCESSOR_WRITE_STATE}.raw.XXXXXX")
    jq '.provenance["docs/r.mdx"].writerReport.authorizedFromHash =
      "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"' \
      "$PROCESSOR_WRITE_STATE" >"$RAW_MARK_TEMP"
    mv "$RAW_MARK_TEMP" "$PROCESSOR_WRITE_STATE"
    printf '%s\n' release >"$MARK_RAW_RELEASE"
    if wait "$MARK_RAW_PID"; then
      contract_failure 'mark-done CAS accepted a raw final-interval authority mutation'
    elif ! rg -qF PROCESSOR_AUTHORITY_INVALID "$MARK_RAW_OUTPUT"; then
      contract_failure 'mark-done raw mutation failed with the wrong refusal'
    fi
  fi
  printf '%s\n' "$AUTH_WRITE_STATE" >"$PROCESSOR_WRITE_STATE"
  if [[ $(authority_snapshot "$PROCESSOR_STATE") != "$MARK_RAW_PROCESSOR_BEFORE" ]]; then
    contract_failure 'mark-done CAS failure replaced processor state'
  fi
  if find "$(dirname "$PROCESSOR_STATE")" -maxdepth 1 -type f \
    -name 'state.json.??????' -print -quit | rg -q .; then
    contract_failure 'mark-done ordinary CAS failure left a temporary state file'
  fi

  SECOND_FILE_BYTES='second complete writer output'
  SECOND_FILE_HASH=$(printf '%s' "$SECOND_FILE_BYTES" | sha256sum | cut -d ' ' -f1)
  printf '%s' "$SECOND_FILE_BYTES" >"$PROCESSOR_REPO/docs/s.mdx"
  SECOND_REPORT=$(jq -cn --arg plan "$PLAN_A" --arg from "$SCAFFOLD_A" \
    --arg written "$SECOND_FILE_HASH" '{
      reportedBy:"docs/s.mdx",authorizedPlanHash:$plan,authorizedFromHash:$from,
      writtenHash:$written,gaps:[]
    }')
  TWO_PATH_PENDING=$(jq -c --arg scaffold "$SCAFFOLD_A" '
    .filesWritten = 0 | .filesTotal = 2 | .writeQueue = ["docs/r.mdx","docs/s.mdx"] |
    .provenance["docs/r.mdx"].writeStatus = "pending" |
    .provenance["docs/r.mdx"].writtenHash = null |
    .provenance["docs/r.mdx"].writerReport = null |
    .provenance["docs/s.mdx"] = {
      origin:"new",scaffoldHash:$scaffold,scaffoldedAt:"2026-08-01T00:00:00Z",
      tier:4,writeStatus:"pending",writtenHash:null,writerReport:null
    }
  ' <<<"$AUTH_WRITE_STATE")
  TWO_PATH_COMMITTED=$(jq -c --arg written "$SECOND_FILE_HASH" \
    --argjson report "$SECOND_REPORT" --arg rWritten "$FILE_HASH" \
    --argjson rReport "$WRITE_REPORT_VALID" '
      .filesWritten = 2 |
      .provenance["docs/r.mdx"].writeStatus = "written" |
      .provenance["docs/r.mdx"].writtenHash = $rWritten |
      .provenance["docs/r.mdx"].writerReport = $rReport |
      .provenance["docs/s.mdx"].writeStatus = "written" |
      .provenance["docs/s.mdx"].writtenHash = $written |
      .provenance["docs/s.mdx"].writerReport = $report
    ' <<<"$TWO_PATH_PENDING")
  printf '%s\n' "$TWO_PATH_PENDING" >"$PROCESSOR_WRITE_STATE"
  if ! printf '%s\n' docs/r.mdx docs/s.mdx | (
    cd "$PROCESSOR_REPO" && bash "$CD_ROOT/scripts/init-state.sh" \
      .contributor-docs/write-tier-4/state.json '["src/r.ts"]' 2 out \
      --plan-hash "$PLAN_A"
  ) >/dev/null; then
    contract_failure 'Could not initialize two-path lost-update fixture'
  fi
  printf '%s\n' "$TWO_PATH_COMMITTED" >"$PROCESSOR_WRITE_STATE"
  TWO_MARK_READY="$BARRIER_ROOT/two-mark.ready"
  TWO_MARK_RELEASE="$BARRIER_ROOT/two-mark.release"
  TWO_MARK_OUTPUT="$BARRIER_ROOT/two-mark.output"
  mkfifo "$TWO_MARK_RELEASE"
  (
    cd "$PROCESSOR_REPO" && env CONTRIBUTOR_DOCS_CONTRACT_TEST=1 \
      CONTRIBUTOR_DOCS_TEST_BARRIER_POINT=mark-before-cas \
      CONTRIBUTOR_DOCS_TEST_ROOT="$BARRIER_ROOT" \
      CONTRIBUTOR_DOCS_TEST_READY_FILE="$TWO_MARK_READY" \
      CONTRIBUTOR_DOCS_TEST_RELEASE_FIFO="$TWO_MARK_RELEASE" \
      bash "$CD_ROOT/scripts/mark-done.sh" \
        .contributor-docs/write-tier-4/state.json docs/r.mdx --plan-hash "$PLAN_A"
  ) >"$TWO_MARK_OUTPUT" 2>&1 &
  TWO_MARK_PID=$!
  if ! wait_for_contract_barrier "$TWO_MARK_READY"; then
    contract_failure 'Two-path mark barrier was not reached'
    kill "$TWO_MARK_PID" 2>/dev/null || true
  else
    if OUTPUT=$(
      cd "$PROCESSOR_REPO" && bash "$CD_ROOT/scripts/mark-done.sh" \
        .contributor-docs/write-tier-4/state.json docs/s.mdx --plan-hash "$PLAN_A" 2>&1
    ); then
      contract_failure 'Second path bypassed an active mark transaction'
    elif [[ $OUTPUT != *AUTHORITY_BUSY* ]]; then
      contract_failure 'Second path contention failed with the wrong refusal'
    fi
    printf '%s\n' release >"$TWO_MARK_RELEASE"
    if ! wait "$TWO_MARK_PID"; then
      contract_failure 'First path failed after two-path barrier release'
    elif ! (
      cd "$PROCESSOR_REPO" && bash "$CD_ROOT/scripts/mark-done.sh" \
        .contributor-docs/write-tier-4/state.json docs/s.mdx --plan-hash "$PLAN_A"
    ) >/dev/null; then
      contract_failure 'Second path retry failed after the first mark committed'
    elif ! jq -e '
      .pendingFiles == [] and
      (.processedFiles | sort) == ["docs/r.mdx","docs/s.mdx"] and
      (.processedFiles | length) == 2
    ' "$PROCESSOR_STATE" >/dev/null; then
      contract_failure 'Concurrent marks lost or duplicated a processed path'
    fi
  fi

  # A killed holder releases the kernel lock automatically; the persistent lock file
  # remains and an ordinary retry succeeds without stale-lock reclamation.
  printf '%s\n' "$PROCESSOR_PENDING_WRITE" >"$PROCESSOR_WRITE_STATE"
  KILL_READY="$BARRIER_ROOT/init-kill.ready"
  KILL_RELEASE="$BARRIER_ROOT/init-kill.release"
  KILL_OUTPUT="$BARRIER_ROOT/init-kill.output"
  mkfifo "$KILL_RELEASE"
  (
    KILL_GIT_DIR=$(git -C "$PROCESSOR_REPO" rev-parse --absolute-git-dir)
    exec {KILL_FD}>"$KILL_GIT_DIR/contributor-docs-authority.lock"
    flock -xn "$KILL_FD"
    : >"$KILL_READY"
    IFS= read -r _ <"$KILL_RELEASE"
  ) >"$KILL_OUTPUT" 2>&1 &
  KILL_PID=$!
  if ! wait_for_contract_barrier "$KILL_READY"; then
    contract_failure 'Killed-holder barrier was not reached'
  else
    kill -9 "$KILL_PID" 2>/dev/null || true
    wait "$KILL_PID" 2>/dev/null || true
    if ! printf '%s\n' 'docs/r.mdx' | (
      cd "$PROCESSOR_REPO" && bash "$CD_ROOT/scripts/init-state.sh" \
        .contributor-docs/write-tier-4/state.json '["src/r.ts"]' 1 out \
        --plan-hash "$PLAN_A"
    ) >/dev/null; then
      contract_failure 'Retry could not acquire the persistent lock after holder death'
    fi
  fi
  PROCESSOR_GIT_DIR=$(git -C "$PROCESSOR_REPO" rev-parse --absolute-git-dir)
  if [[ ! -f $PROCESSOR_GIT_DIR/contributor-docs-authority.lock ]]; then
    contract_failure 'Authority lock file was unlinked instead of left persistent'
  fi
  find "$(dirname "$PROCESSOR_STATE")" -maxdepth 1 -type f \
    -name 'state.json.??????' -delete

  if [[ $FAILURES -eq $CONTROL_FAILURES_BEFORE ]]; then
    echo '✅ Shared lock, contention, death release, and final-interval CAS controls passed for both helpers'
  fi

  RECORD_WRITE_DEF_COUNT=$(rg -c '^def cd_record_write_authority' \
    "$CD_ROOT/scripts/init-state.sh" || true)
  if [[ $RECORD_WRITE_DEF_COUNT != 1 ]] ||
    rg -q '^[[:space:]]*def writer_report|^[[:space:]]*assert_processor_completion_authority\(\)' \
      "$CD_ROOT/scripts/init-state.sh" "$CD_ROOT/scripts/mark-done.sh"; then
    contract_failure 'Shared record-write predicate was duplicated or shadowed'
  fi

  for LITERAL in authorizedPlanHash authorize-gap-plan apply-gap-plan PLAN_DRIFT_BLOCKED \
    GAP_PLAN_DELTA_INVALID GAP_PLAN_HASH_INVALID GAP_PLAN_CANDIDATE_MISSING \
    GAP_REPORT_SET_INVALID GAP_CLOSURE_INVALID GAP_LOOP WRITE_REPORT_MISSING \
    PROCESSOR_AUTHORITY_INVALID AUTHORITY_BUSY recordWriteAuthorizations; do
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

[[ $# -eq 6 && $5 == "--plan-hash" && $6 =~ ^[0-9a-f]{64}$ ]] || {
  echo "❌ Usage: <file-list> | init-state.sh <state-file> <source-paths-json> <concurrent> <output-dir> --plan-hash <64-hex>" >&2
  exit 1
}

STATE_FILE="$1"
SOURCE_PATHS="$2"
CONCURRENT="$3"
OUTPUT_DIR="$4"
PLAN_HASH="$6"

FILES_JSON=$(jq -R -s 'split("\n") | map(select(. != ""))')
acquire_authority_lock
trap 'authority_transaction_cleanup "$?"' EXIT

RECORD_WRITE_AUTHORIZATIONS=$(
  assert_processor_init_authority "$PLAN_HASH" "$STATE_FILE" "$FILES_JSON"
)

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
AUTHORITY_PREIMAGE=$(processor_authority_snapshot "$STATE_FILE")
PROCESSOR_PREIMAGE=$(authority_snapshot "$STATE_FILE")

# Written through a temp file in the destination directory so an interrupted run
# never leaves a half-written state file behind.
CONTRIBUTOR_DOCS_TEMP_FILE=$(mktemp "${STATE_FILE}.XXXXXX")
jq -n \
  --argjson sourcePaths "$SOURCE_PATHS" \
  --arg outputDir "$OUTPUT_DIR" \
  --argjson concurrent "$CONCURRENT" \
  --argjson files "$FILES_JSON" \
  --argjson recordWriteAuthorizations "$RECORD_WRITE_AUTHORIZATIONS" \
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
    authorizedPlanHash: $planHash,
    recordWriteAuthorizations: $recordWriteAuthorizations
  }' >"$CONTRIBUTOR_DOCS_TEMP_FILE"

FRESH_RECORD_WRITE_AUTHORIZATIONS=$(
  assert_processor_init_authority "$PLAN_HASH" "$STATE_FILE" "$FILES_JSON"
)
if [[ $FRESH_RECORD_WRITE_AUTHORIZATIONS != "$RECORD_WRITE_AUTHORIZATIONS" ]] ||
  ! jq -e --argjson sourcePaths "$SOURCE_PATHS" --arg outputDir "$OUTPUT_DIR" \
    --argjson concurrent "$CONCURRENT" --argjson files "$FILES_JSON" \
    --arg planHash "$PLAN_HASH" \
    --argjson authorizations "$RECORD_WRITE_AUTHORIZATIONS" '
      ((keys | sort) == (["sourcePaths","outputDir","concurrentAgents","filesToProcess",
        "processedFiles","pendingFiles","startTime","authorizedPlanHash",
        "recordWriteAuthorizations"] | sort)) and
      .sourcePaths == $sourcePaths and .outputDir == $outputDir and
      .concurrentAgents == $concurrent and .filesToProcess == $files and
      .processedFiles == [] and .pendingFiles == $files and
      .authorizedPlanHash == $planHash and
      .recordWriteAuthorizations == $authorizations and
      (.startTime | type == "string" and
        test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$"))
    ' "$CONTRIBUTOR_DOCS_TEMP_FILE" >/dev/null; then
  echo "PROCESSOR_AUTHORITY_INVALID: staged processor state is not bound to fresh authority" >&2
  exit 1
fi

authority_contract_test_barrier init-before-cas
if [[ $(processor_authority_snapshot "$STATE_FILE") != "$AUTHORITY_PREIMAGE" ]] ||
  [[ $(authority_snapshot "$STATE_FILE") != "$PROCESSOR_PREIMAGE" ]]; then
  echo "PROCESSOR_AUTHORITY_INVALID: authority or processor preimage changed before initialization commit" >&2
  exit 1
fi
mv "$CONTRIBUTOR_DOCS_TEMP_FILE" "$STATE_FILE"
CONTRIBUTOR_DOCS_TEMP_FILE=
release_authority_lock
trap - EXIT

echo "✅ Initialized with $(jq length <<<"$FILES_JSON") files"
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
  init_state_main "$@"
fi
