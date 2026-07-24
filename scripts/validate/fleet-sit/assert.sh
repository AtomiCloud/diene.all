#!/usr/bin/env bash

sit_fail() {
  echo "fleet SIT assertion failed: $*" >&2
  return 1
}

sit_require_command() {
  command -v "$1" >/dev/null 2>&1 || sit_fail "required command is missing: $1"
}

sit_now() {
  date -u +%Y-%m-%dT%H:%M:%SZ
}

sit_epoch() {
  date -u +%s
}

sit_wait_for() {
  local timeout_s="$1"
  local description="$2"
  shift 2
  local deadline=$((SECONDS + timeout_s))

  while true; do
    if "$@"; then
      return 0
    fi
    if [ "${SECONDS}" -ge "${deadline}" ]; then
      sit_fail "timed out after ${timeout_s}s waiting for ${description}"
      return 1
    fi
    sleep "${FLEET_SIT_POLL_SECONDS:-3}"
  done
}

sit_report_init() {
  local report_dir="$1"
  local argocd_version="$2"
  local argocd_source_commit="$3"
  local manifest_sha256="$4"
  local k3s_image="$5"
  local source_head="$6"
  local implementation_sha256="$7"
  local implementation_uncommitted="$8"
  local implementation_file_count="$9"

  SIT_REPORT_DIR="${report_dir}"
  SIT_REPORT_FILE="${report_dir}/sit-report.json"
  SIT_RUN_STARTED_EPOCH="$(sit_epoch)"
  SIT_CURRENT_LEG=''
  SIT_CURRENT_LEG_STARTED_EPOCH=''
  SIT_CURRENT_LEG_STARTED=''
  SIT_LEG_EVIDENCE=()
  mkdir -p "${SIT_REPORT_DIR}"

  jq -n \
    --arg argocd "${argocd_version}" \
    --arg argocdSourceCommit "${argocd_source_commit}" \
    --arg manifestSha256 "${manifest_sha256}" \
    --arg k3s "${k3s_image}" \
    --arg commit "${source_head}" \
    --arg implementationSha256 "${implementation_sha256}" \
    --argjson implementationUncommitted "${implementation_uncommitted}" \
    --argjson implementationFileCount "${implementation_file_count}" \
    --arg started "$(sit_now)" \
    '{
      schemaVersion: 1,
      status: "running",
      argocd: $argocd,
      argocdSourceCommit: $argocdSourceCommit,
      argocdManifestSha256: $manifestSha256,
      k3s: $k3s,
      commit: $commit,
      implementationSha256: $implementationSha256,
      implementationInventory: "implementation-inventory.sha256",
      implementationHashAlgorithm: "sha256 of LF-delimited <file-sha256><two spaces><relative-path> inventory lines sorted bytewise by path",
      implementationFileCount: $implementationFileCount,
      implementationUncommittedAtProof: $implementationUncommitted,
      started: $started,
      legs: [],
      residuals: [
        "seven-landscape manual DAG sync not executed (user-gated; the unavailable OCI workloads make the tail non-runnable)",
        "real scmProvider/GitHub repository listing not exercised; a list-generator variant is reverse-diff-asserted against the committed ApplicationSet",
        "per-row OCI workload sync not exercised because registry.atomi.cloud artifacts are unavailable; row assertions stop at generated Application specs"
      ],
      deviations: [
        "the throwaway fleet mirror relaxes only values.schema.json fleet.repoURL from ^https:// to ^https?:// because its hermetic smart-HTTP endpoint is cluster-local HTTP without a TLS layer",
        "the throwaway argocd-server sets server.insecure=true because the pinned install port-80 Service targets its default self-signed TLS listener; this permits hermetic HTTP webhook delivery without weakening signature validation",
        "the derived local ApplicationSet maps the explicit-port production identity for source C to fleet-services.git, an in-root symlink to fleet.git, while source A uses fleet.git; this preserves source C at HEAD while avoiding the pinned Argo same-identity different-revision rejection",
        "before L5 the throwaway harness stops both the Application and ApplicationSet controllers, clears the resources finalizer only on platform-sitother, deletes it while neither controller can restore that finalizer, then restores and explicitly refreshes its owning ApplicationSet; this recreates an operation-free UID and clears the intentionally CRD-light initial retry before the tag moves",
        "L7 shortens both the ApplicationSet generator requeue and the repo-server repo-state cache expiration to 30s; these are the two pinned production polling layers, and matching them makes the real no-webhook fallback runnable within the bounded throwaway test",
        "the pinned Argo install uses server-side apply because its ApplicationSet CRD is larger than Kubernetes permits in a client-side last-applied annotation",
        "the planned static dumb-HTTP fixture transport was replaced after source and runtime verification: Argo CD v3.4.5 go-git remote.List rejects its static info/refs response, so the Bun wrapper invokes git http-backend for smart HTTP"
      ],
      feasibility: {
        applicationSetWebhookPort: 7000,
        applicationWebhookServicePort: 80,
        applicationWebhookRuntimeTransport: "HTTP after server.insecure=true in the throwaway cluster",
        githubSecretKey: "webhook.github.secret",
        webhookNegativeOracle: "wrong and missing signatures must return pinned HTTP 400 rejection responses and cause no Application spec refresh",
        applicationSetRefreshBypassesRevisionCache: true,
        pollingPhaseRestartsRepoServer: true,
        pollingPhaseApplicationSetRequeue: "30s",
        pollingPhaseRepoCacheExpiration: "30s",
        nonCanaryAutomationOracle: "a newly recreated Application UID with source-A comparison at C4, root and status controller-initiated automatic operations pinned to C4, and operation start at or after the tag-move timestamp",
        sameRepositoryDifferentRevisionConstraint: "Argo CD v3.4.5 rejects different revisions when source URLs normalize to one identity",
        fleetServicesAlias: "fleet-services.git symlink to fleet.git with identical advertised refs and a distinct URL identity",
        gitTransport: "smart HTTP via Bun CGI wrapper around git http-backend",
        argocdRefDiscovery: "pinned util/git/client.go getRefs initializes go-git in-memory storage and calls remote.List through listRemote; it does not shell out to git"
      }
    }' >"${SIT_REPORT_FILE}"
}

_sit_evidence_json() {
  if [ "${#SIT_LEG_EVIDENCE[@]}" -eq 0 ]; then
    printf '[]\n'
    return
  fi
  printf '%s\n' "${SIT_LEG_EVIDENCE[@]}" | jq -Rsc 'split("\n")[:-1]'
}

_sit_report_replace() {
  local replacement="$1"
  local tmp="${SIT_REPORT_FILE}.tmp.$$"
  printf '%s\n' "${replacement}" >"${tmp}"
  mv "${tmp}" "${SIT_REPORT_FILE}"
}

sit_leg_begin() {
  SIT_CURRENT_LEG="$1"
  shift
  SIT_CURRENT_LEG_STARTED_EPOCH="$(sit_epoch)"
  SIT_CURRENT_LEG_STARTED="$(sit_now)"
  SIT_LEG_EVIDENCE=("$@")
  echo "==> ${SIT_CURRENT_LEG}"
}

sit_leg_pass() {
  local note="${1:-}"
  local evidence_path
  for evidence_path in "${SIT_LEG_EVIDENCE[@]}"; do
    case "${evidence_path}" in
    /* | .. | ../* | */.. | */../*)
      sit_fail "invalid report evidence path: ${evidence_path}"
      return 1
      ;;
    esac
    [ -s "${SIT_REPORT_DIR}/${evidence_path}" ] || {
      sit_fail "claimed report evidence is missing or empty: ${evidence_path}"
      return 1
    }
  done
  local elapsed=$(($(sit_epoch) - SIT_CURRENT_LEG_STARTED_EPOCH))
  local evidence
  evidence="$(_sit_evidence_json)"
  local updated
  updated="$(jq \
    --arg leg "${SIT_CURRENT_LEG}" \
    --arg started "${SIT_CURRENT_LEG_STARTED}" \
    --arg note "${note}" \
    --argjson elapsed "${elapsed}" \
    --argjson evidence "${evidence}" \
    '.legs += [{leg:$leg,status:"pass",started:$started,elapsed_s:$elapsed,evidence:$evidence,note:$note}]' \
    "${SIT_REPORT_FILE}")"
  _sit_report_replace "${updated}"
  echo "<== ${SIT_CURRENT_LEG} passed (${elapsed}s)"
  SIT_CURRENT_LEG=''
  SIT_LEG_EVIDENCE=()
}

sit_leg_fail() {
  local exit_code="$1"
  local reason="$2"
  [ -n "${SIT_CURRENT_LEG:-}" ] || return 0
  local elapsed=$(($(sit_epoch) - SIT_CURRENT_LEG_STARTED_EPOCH))
  local evidence
  evidence="$(_sit_evidence_json)"
  local updated
  updated="$(jq \
    --arg leg "${SIT_CURRENT_LEG}" \
    --arg started "${SIT_CURRENT_LEG_STARTED}" \
    --arg reason "${reason}" \
    --argjson exitCode "${exit_code}" \
    --argjson elapsed "${elapsed}" \
    --argjson evidence "${evidence}" \
    '.legs += [{leg:$leg,status:"fail",started:$started,elapsed_s:$elapsed,evidence:$evidence,exitCode:$exitCode,reason:$reason}]' \
    "${SIT_REPORT_FILE}")"
  _sit_report_replace "${updated}"
  SIT_CURRENT_LEG=''
  SIT_LEG_EVIDENCE=()
}

sit_report_finish() {
  local status="$1"
  local elapsed=$(($(sit_epoch) - SIT_RUN_STARTED_EPOCH))
  local updated
  updated="$(jq \
    --arg status "${status}" \
    --arg completed "$(sit_now)" \
    --argjson elapsed "${elapsed}" \
    '.status=$status | .completed=$completed | .elapsed_s=$elapsed' \
    "${SIT_REPORT_FILE}")"
  _sit_report_replace "${updated}"
}

sit_snapshot_apps() {
  kubectl -n argocd get applications.argoproj.io -o json >"$1"
}

sit_child_specs() {
  jq '
    [.items[] |
      select(any(.metadata.ownerReferences[]?; .kind == "ApplicationSet" and .name == "canary")) |
      {name:.metadata.name,spec:.spec}
    ] | sort_by(.name)
  ' "$1" >"$2"
}

sit_changed_names() {
  jq -n \
    --slurpfile before "$1" \
    --slurpfile after "$2" '
      ($before[0] | map({key:.name,value:.spec}) | from_entries) as $b |
      ($after[0] | map({key:.name,value:.spec}) | from_entries) as $a |
      ((($b | keys) + ($a | keys)) | unique |
        map(. as $name | select($b[$name] != $a[$name])))
    ' >"$3"
}

sit_assert_json_equal() {
  local expected="$1"
  local actual="$2"
  local description="$3"
  if ! cmp -s "${expected}" "${actual}"; then
    diff -u "${expected}" "${actual}" >&2 || true
    sit_fail "${description}"
    return 1
  fi
}

sit_assert_http_success() {
  jq -e '.status >= 200 and .status < 300 and .ok == true' "$1" >/dev/null ||
    sit_fail "signed webhook did not return a successful HTTP status: $1"
}

sit_assert_http_rejected() {
  local signature_mode="$1"
  local response_regex="$2"
  local evidence="$3"
  jq -e --arg mode "${signature_mode}" --arg responseRegex "${response_regex}" '
    .signatureMode == $mode and
    .status == 400 and
    .ok == false and
    (.responseBody | test($responseRegex; "i"))
  ' "${evidence}" >/dev/null ||
    sit_fail "${signature_mode} webhook was not rejected with the pinned HTTP 400 contract: ${evidence}"
}

sit_assert_complete_pass_legs() {
  jq -e '
    .status == "running" and
    [.legs[].leg] == [
      "L0-runtime-setup",
      "L1-baseline-generation",
      "L2-signed-webhook-one-row",
      "L3-invalid-signatures-no-refresh",
      "L4-main-tag-and-manual-policy",
      "L5-machinery-tag-and-automated-policy",
      "L6-two-row-union-and-no-row",
      "L7-polling-fallback"
    ] and
    all(.legs[]; .status == "pass" and (.evidence | length) > 0)
  ' "${SIT_REPORT_FILE}" >/dev/null ||
    sit_fail 'final SIT report does not contain the exact ordered L0-L7 pass set'
}

sit_assert_child_specs_stable_for() {
  local duration_s="$1"
  local baseline="$2"
  local failure_evidence="$3"
  local scratch
  scratch="$(mktemp -d "${SIT_REPORT_DIR}/.stable.XXXXXX")"
  local deadline=$((SECONDS + duration_s))

  while [ "${SECONDS}" -lt "${deadline}" ]; do
    sit_snapshot_apps "${scratch}/apps.json"
    sit_child_specs "${scratch}/apps.json" "${scratch}/specs.json"
    if ! cmp -s "${baseline}" "${scratch}/specs.json"; then
      cp "${scratch}/apps.json" "${failure_evidence}"
      diff -u "${baseline}" "${scratch}/specs.json" >"${failure_evidence}.diff" || true
      rm -rf "${scratch}"
      sit_fail "Application specs changed during a bounded no-refresh interval"
      return 1
    fi
    sleep "${FLEET_SIT_POLL_SECONDS:-3}"
  done
  rm -rf "${scratch}"
}
