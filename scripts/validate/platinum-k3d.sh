#!/usr/bin/env bash
# Integration-tier proof (k3d + live kgateway). NOT part of the unit tier; run only in the
# serialized quiet-host proof window. Proves Gateway Programmed=True, the /healthz route answers 2xx
# through the shared Gateway, and the chart round-trips through a local OCI registry.
set -euo pipefail

if [ "${K3D_ISOLATE_BY_PATH:-false}" = "true" ]; then
  isolation_key="$(printf '%s' "${PWD}" | sha256sum | cut -c1-8)"
  export K3D_CLUSTER_NAME="${K3D_CLUSTER_NAME:-platinum-${isolation_key}}"
  export K3D_REGISTRY_NAME="${K3D_REGISTRY_NAME:-platinum-registry-${isolation_key}}"
  export K3D_REGISTRY_PORT="${K3D_REGISTRY_PORT:-$((20000 + (16#${isolation_key:0:4} % 10000)))}"
  export K3D_HTTP_PORT="${K3D_HTTP_PORT:-$((30000 + (16#${isolation_key:4:4} % 10000)))}"
fi

cluster_name="${K3D_CLUSTER_NAME:-platinum}"
registry_port="${K3D_REGISTRY_PORT:-5001}"
http_port="${K3D_HTTP_PORT:-18080}"
evidence_dir="${PLATINUM_EVIDENCE_DIR:?set PLATINUM_EVIDENCE_DIR to an absolute durable directory}"
case "${evidence_dir}" in
/*) ;;
*)
  echo "❌ PLATINUM_EVIDENCE_DIR must be absolute" >&2
  exit 1
  ;;
esac
mkdir -p "${evidence_dir}"
archive_path="${evidence_dir}/platinum-0.1.0.tgz"
archive_sha_path="${evidence_dir}/platinum-0.1.0.tgz.sha256"
tmp="$(mktemp -d)"

# RB-333 bounded readiness/failure envelope (seconds): Helm readiness 900 +
# Gateway Programmed 600 + endpoint/health readiness 300 + one shared 300-second
# diagnostics-and-cleanup deadline = 2100 total worst case. The deadline
# includes timeout kill grace and leaves 5100 seconds for the existing
# non-binding cluster/CRD/OCI work inside the unchanged 7200-second shard.
readonly helm_readiness_timeout_seconds=900
readonly gateway_readiness_timeout_seconds=600
readonly health_readiness_timeout_seconds=300
readonly total_worst_case_budget_seconds=2100
readonly shard_hard_timeout_seconds=7200
readonly production_failure_handling_budget_seconds=300

failure_handling_budget_seconds="${production_failure_handling_budget_seconds}"
failure_kill_grace_seconds=2
cleanup_reserve_seconds=120
diagnostic_command_max_seconds=20
diagnostic_byte_limit=32768
if [ "${PLATINUM_BEHAVIOR_TEST:-false}" = "true" ]; then
  failure_handling_budget_seconds="${PLATINUM_TEST_FAILURE_BUDGET_SECONDS:-${failure_handling_budget_seconds}}"
  failure_kill_grace_seconds="${PLATINUM_TEST_KILL_GRACE_SECONDS:-${failure_kill_grace_seconds}}"
  cleanup_reserve_seconds="${PLATINUM_TEST_CLEANUP_RESERVE_SECONDS:-${cleanup_reserve_seconds}}"
  diagnostic_command_max_seconds="${PLATINUM_TEST_DIAGNOSTIC_COMMAND_MAX_SECONDS:-${diagnostic_command_max_seconds}}"
  diagnostic_byte_limit="${PLATINUM_TEST_DIAGNOSTIC_BYTE_LIMIT:-${diagnostic_byte_limit}}"
fi
readonly failure_handling_budget_seconds
readonly failure_kill_grace_seconds
readonly cleanup_reserve_seconds
readonly diagnostic_command_max_seconds
readonly diagnostic_byte_limit

for bounded_integer in \
  "${failure_handling_budget_seconds}" \
  "${failure_kill_grace_seconds}" \
  "${cleanup_reserve_seconds}" \
  "${diagnostic_command_max_seconds}" \
  "${diagnostic_byte_limit}"; do
  if [[ ! ${bounded_integer} =~ ^[1-9][0-9]*$ ]]; then
    echo "❌ Platinum failure budget values must be positive integers" >&2
    exit 1
  fi
done
if ((cleanup_reserve_seconds + failure_kill_grace_seconds >= failure_handling_budget_seconds)); then
  echo "❌ Platinum cleanup reserve and kill grace exhaust the failure deadline" >&2
  exit 1
fi
if ((total_worst_case_budget_seconds != helm_readiness_timeout_seconds + gateway_readiness_timeout_seconds + health_readiness_timeout_seconds + production_failure_handling_budget_seconds)); then
  echo "❌ Platinum proof budget components do not match the documented total" >&2
  exit 1
fi
if ((total_worst_case_budget_seconds >= shard_hard_timeout_seconds)); then
  echo "❌ Platinum proof budget exhausts the shard hard timeout" >&2
  exit 1
fi

bounded_health_request_seconds() {
  local deadline="$1"
  local remaining=$((deadline - SECONDS))

  if ((remaining <= 0)); then
    return 1
  fi
  if ((remaining > 5)); then
    remaining=5
  fi
  printf '%s\n' "${remaining}"
}

deadline_run_seconds() {
  local deadline="$1"
  local reserve_seconds="$2"
  local command_cap_seconds="$3"
  local run_seconds=$((deadline - SECONDS - reserve_seconds - failure_kill_grace_seconds))

  if ((run_seconds <= 0)); then
    return 1
  fi
  if ((run_seconds > command_cap_seconds)); then
    run_seconds="${command_cap_seconds}"
  fi
  printf '%s\n' "${run_seconds}"
}

cap_diagnostic_lines() {
  local output_path="$1"

  LC_ALL=C awk -v limit="${diagnostic_byte_limit}" '
    {
      record_bytes = length($0) + 1
      if (written_bytes + record_bytes > limit) {
        exit
      }
      print
      written_bytes += record_bytes
    }
  ' >"${output_path}"
}

capture_diagnostic_file() {
  local failure_deadline="$1"
  local output_path="$2"
  local run_seconds pipeline_status
  shift 2

  : >"${output_path}" || return 0
  if ! run_seconds="$(deadline_run_seconds "${failure_deadline}" "${cleanup_reserve_seconds}" "${diagnostic_command_max_seconds}")"; then
    printf '124\n' >"${output_path}.exit" || true
    return 0
  fi

  if timeout --signal=TERM --kill-after="${failure_kill_grace_seconds}" "${run_seconds}s" "$@" 2>/dev/null |
    cap_diagnostic_lines "${output_path}"; then
    pipeline_status=0
  else
    pipeline_status="$?"
  fi
  printf '%s\n' "${pipeline_status}" >"${output_path}.exit" || true
}

# Fixed-schema, privacy-safe summary of a controller log stream. Reads the
# bounded raw log on stdin and emits ONLY derived, non-reversible fields: a
# SHA-256 of the raw bytes, byte/line counts, and per-category match counts over
# a closed, documented crash vocabulary. No original line body is ever emitted,
# so no secret/bearer/JWT/key/URL/DSN/high-entropy value in the log can survive
# into the durable artifact. Category matching is a documented allowlist of
# fixed, case-insensitive patterns; only integer counts leave this function.
summarize_controller_log() {
  local raw bytes lines sha
  raw="$(cat)"
  bytes="$(printf '%s' "${raw}" | wc -c | tr -d ' ')"
  if [ -z "${raw}" ]; then
    lines=0
  else
    lines="$(printf '%s\n' "${raw}" | wc -l | tr -d ' ')"
  fi
  sha="$(printf '%s' "${raw}" | sha256sum | cut -d' ' -f1)"
  _cat_count() {
    if [ -z "${raw}" ]; then
      printf '0'
    else
      printf '%s' "${raw}" | grep -icE "$1" || true
    fi
  }
  printf 'schema\tcontroller-crash-summary-v1\n'
  printf 'raw_sha256\t%s\n' "${sha}"
  printf 'raw_byte_count\t%s\n' "${bytes}"
  printf 'raw_line_count\t%s\n' "${lines}"
  printf 'cat_panic\t%s\n' "$(_cat_count 'panic:|goroutine [0-9]|runtime error|invalid memory address|nil pointer')"
  printf 'cat_oom\t%s\n' "$(_cat_count 'out of memory|oomkill|cannot allocate memory|runtime: out of memory')"
  printf 'cat_permission\t%s\n' "$(_cat_count 'forbidden|permission denied|unauthorized|cannot (list|get|watch|create|update)|is forbidden|rbac')"
  printf 'cat_connectivity\t%s\n' "$(_cat_count 'connection refused|no route to host|dial tcp|i/o timeout|context deadline exceeded|econnrefused|network is unreachable')"
  printf 'cat_config\t%s\n' "$(_cat_count 'invalid config|failed to parse|cannot unmarshal|decode error|unknown field|validation failed|no such file or directory')"
  printf 'cat_probe\t%s\n' "$(_cat_count 'readyz|healthz|readiness|liveness|probe failed|startup probe')"
  printf 'cat_tls\t%s\n' "$(_cat_count 'x509|tls handshake|bad certificate|certificate signed by unknown')"
  printf 'cat_fatal\t%s\n' "$(_cat_count 'level=fatal|"level":"fatal"|fatal error|^fatal|[[:space:]]fatal[[:space:]]')"
}

# Deterministically resolve the single release-owned crashing controller pod
# from its own restart/lastState evidence, BEFORE any pod-targeted capture. A
# crashing candidate is a release-selected pod whose container named `controller`
# has restartCount >= 1 AND (waiting reason CrashLoopBackOff OR a numeric
# lastState.terminated.exitCode). On exactly one candidate its name is printed;
# on zero or multiple it fails closed with a bounded ambiguity artifact and no
# fallback to deployment shorthand or namespace-wide events.
resolve_crashing_controller_pod() {
  local failure_deadline="$1"
  local diagnostics_dir="$2"
  local run_seconds listing candidates count
  if ! run_seconds="$(deadline_run_seconds "${failure_deadline}" "${cleanup_reserve_seconds}" "${diagnostic_command_max_seconds}")"; then
    printf 'schema\tcontroller-ambiguity-v1\nreason\tdeadline\ncandidates\t0\n' |
      cap_diagnostic_lines "${diagnostics_dir}/controller-ambiguity.tsv"
    return 1
  fi
  listing="$(timeout --signal=TERM --kill-after="${failure_kill_grace_seconds}" "${run_seconds}s" \
    kubectl --context "k3d-${cluster_name}" --namespace sulfoxide --request-timeout=15s \
    get pods --selector 'app.kubernetes.io/instance in (platinum,platinum-gateway)' \
    -o 'jsonpath={range .items[*]}{.metadata.name}{"\t"}{range .status.containerStatuses[?(@.name=="controller")]}{.restartCount}{":"}{.state.waiting.reason}{":"}{.lastState.terminated.exitCode}{":"}{.lastState.terminated.reason}{end}{"\n"}{end}' 2>/dev/null)" || true
  candidates="$(printf '%s\n' "${listing}" | awk -F'\t' '
    NF >= 2 && $2 != "" {
      split($2, c, ":")
      if (c[1] ~ /^[0-9]+$/ && c[1] + 0 >= 1 && (c[2] == "CrashLoopBackOff" || c[3] ~ /^[0-9]+$/)) {
        print $1
      }
    }' | sort -u | sed '/^$/d')"
  count="$(printf '%s\n' "${candidates}" | sed '/^$/d' | wc -l | tr -d ' ')"
  if [ "${count}" -ne 1 ]; then
    {
      printf 'schema\tcontroller-ambiguity-v1\n'
      printf 'reason\t%s\n' "$([ "${count}" -eq 0 ] && printf none || printf multiple)"
      printf 'candidates\t%s\n' "${count}"
      printf '%s\n' "${candidates}" | sed '/^$/d' | sed 's/^/candidate\t/'
    } | cap_diagnostic_lines "${diagnostics_dir}/controller-ambiguity.tsv"
    return 1
  fi
  printf '%s\n' "${candidates}"
  return 0
}

# Bounded previous-instance controller log capture for one exact pod. The raw
# stream is line/byte capped upstream (--previous --tail --limit-bytes) and is
# summarized in-process by summarize_controller_log; the raw text never touches
# durable storage. A missing previous instance fails safely to a zero-count
# summary plus a nonzero .exit, never altering the proof result.
capture_controller_log_summary() {
  local failure_deadline="$1"
  local output_path="$2"
  local pod="$3"
  local run_seconds pipeline_status
  : >"${output_path}" || return 0
  if ! run_seconds="$(deadline_run_seconds "${failure_deadline}" "${cleanup_reserve_seconds}" "${diagnostic_command_max_seconds}")"; then
    printf '124\n' >"${output_path}.exit" || true
    return 0
  fi
  if timeout --signal=TERM --kill-after="${failure_kill_grace_seconds}" "${run_seconds}s" \
    kubectl --context "k3d-${cluster_name}" --namespace sulfoxide --request-timeout=15s \
    logs "${pod}" --container controller --previous --tail=200 --limit-bytes="${diagnostic_byte_limit}" 2>/dev/null |
    summarize_controller_log >"${output_path}"; then
    pipeline_status=0
  else
    pipeline_status="$?"
  fi
  printf '%s\n' "${pipeline_status}" >"${output_path}.exit" || true
  return 0
}

capture_failure_diagnostics() {
  local proof_status="$1"
  local failure_deadline="$2"
  local diagnostics_dir="${evidence_dir}/failure-diagnostics"
  local controller_pod

  mkdir -p "${diagnostics_dir}" || {
    echo "⚠️ unable to create Platinum failure diagnostics directory" >&2
    return 0
  }

  {
    printf 'proof_exit_status=%s\n' "${proof_status}"
    printf 'captured_at_utc=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf 'per_file_byte_limit=%s\n' "${diagnostic_byte_limit}"
    printf 'failure_deadline_seconds=%s\n' "${failure_handling_budget_seconds}"
  } | cap_diagnostic_lines "${diagnostics_dir}/metadata.tsv" 2>/dev/null || true

  # Persist only release-scoped projections. No manifests, values, annotations,
  # environment, command arguments, event messages, descriptions, or raw
  # container log bodies are captured. The RB-333 CrashLoopBackOff controller
  # log is retained only as a fixed-schema derived summary (SHA-256 + byte/line
  # counts + closed crash-category counts, no line bodies) built below; the raw
  # stdout never reaches durable storage. stderr is discarded and every
  # whole-line TSV file is byte-capped.
  # $1/$2 expand only inside the isolated child shell.
  # shellcheck disable=SC2016
  capture_diagnostic_file "${failure_deadline}" "${diagnostics_dir}/helm-release.tsv" \
    /bin/bash -o pipefail -c '
      helm list --kube-context "$1" --namespace "$2" --all --filter "^platinum$" --output json |
        jq -r '\'' .[] | [(.name // ""), (.namespace // ""), ((.revision // 0) | tostring), (.updated // ""), (.status // ""), (.chart // ""), (.app_version // "")] | @tsv '\''
    ' _ "k3d-${cluster_name}" sulfoxide
  capture_diagnostic_file "${failure_deadline}" "${diagnostics_dir}/workloads.tsv" \
    kubectl --context "k3d-${cluster_name}" --namespace sulfoxide --request-timeout=15s \
    get deployments,statefulsets,daemonsets,jobs --selector 'app.kubernetes.io/instance in (platinum,platinum-gateway)' \
    -o 'jsonpath={range .items[*]}{.kind}{"\t"}{.metadata.namespace}{"\t"}{.metadata.name}{"\t"}{.metadata.generation}{"\t"}{.status.observedGeneration}{"\t"}{.status.replicas}{"\t"}{.status.readyReplicas}{"\t"}{range .status.conditions[*]}{.type}{"="}{.status}{":"}{.reason}{","}{end}{"\n"}{end}'
  capture_diagnostic_file "${failure_deadline}" "${diagnostics_dir}/pods.tsv" \
    kubectl --context "k3d-${cluster_name}" --namespace sulfoxide --request-timeout=15s \
    get pods --selector 'app.kubernetes.io/instance in (platinum,platinum-gateway)' \
    -o 'jsonpath={range .items[*]}{.metadata.namespace}{"\t"}{.metadata.name}{"\t"}{.status.phase}{"\t"}{range .status.conditions[*]}{.type}{"="}{.status}{":"}{.reason}{","}{end}{"\t"}{range .status.containerStatuses[*]}{.name}{":ready="}{.ready}{":restarts="}{.restartCount}{":waiting="}{.state.waiting.reason}{":terminated="}{.state.terminated.reason}{":exit="}{.state.terminated.exitCode}{":lastterminated="}{.lastState.terminated.reason}{":lastexit="}{.lastState.terminated.exitCode}{":lastsignal="}{.lastState.terminated.signal}{","}{end}{"\n"}{end}'
  capture_diagnostic_file "${failure_deadline}" "${diagnostics_dir}/gateway.tsv" \
    kubectl --context "k3d-${cluster_name}" --namespace sulfoxide --request-timeout=15s \
    get gateway platinum-gateway \
    -o 'jsonpath={.kind}{"\t"}{.metadata.namespace}{"\t"}{.metadata.name}{"\t"}{.metadata.generation}{"\t"}{.status.observedGeneration}{"\t"}{range .status.conditions[*]}{.type}{"="}{.status}{":"}{.reason}{","}{end}{"\t"}{range .status.listeners[*]}{.name}{":routes="}{.attachedRoutes}{":"}{range .conditions[*]}{.type}{"="}{.status}{":"}{.reason}{","}{end}{";"}{end}{"\n"}'
  capture_diagnostic_file "${failure_deadline}" "${diagnostics_dir}/gateway-events.tsv" \
    kubectl --context "k3d-${cluster_name}" --namespace sulfoxide --request-timeout=15s \
    get events --field-selector involvedObject.kind=Gateway,involvedObject.name=platinum-gateway \
    -o 'jsonpath={range .items[*]}{.type}{"\t"}{.reason}{"\t"}{.count}{"\t"}{.eventTime}{"\t"}{.lastTimestamp}{"\t"}{.involvedObject.kind}{"\t"}{.involvedObject.name}{"\t"}{.source.component}{"\t"}{.reportingController}{"\n"}{end}'

  # RB-333 CrashLoopBackOff root-cause fields. The prior projections show THAT
  # the platinum-upstream controller restarts, not WHY. Resolve the exact
  # release-owned crashing controller pod first (from its restart/lastState
  # evidence). Only if exactly one is found do we take the two pod-targeted
  # captures within the same deadline/byte envelope: a privacy-safe summary of
  # the previous crashed instance's stdout (no raw line bodies persisted), and
  # Warning events for THAT exact pod (reason only, no free-text message). Zero
  # or multiple crashing candidates fail closed to a bounded ambiguity artifact;
  # we never fall back to deployment shorthand or namespace-wide event scope.
  if controller_pod="$(resolve_crashing_controller_pod "${failure_deadline}" "${diagnostics_dir}")"; then
    capture_controller_log_summary "${failure_deadline}" "${diagnostics_dir}/controller-crash-summary.tsv" "${controller_pod}"
    capture_diagnostic_file "${failure_deadline}" "${diagnostics_dir}/upstream-events.tsv" \
      kubectl --context "k3d-${cluster_name}" --namespace sulfoxide --request-timeout=15s \
      get events --field-selector "involvedObject.kind=Pod,involvedObject.name=${controller_pod},type=Warning" \
      -o 'jsonpath={range .items[*]}{.type}{"\t"}{.reason}{"\t"}{.count}{"\t"}{.eventTime}{"\t"}{.lastTimestamp}{"\t"}{.involvedObject.kind}{"\t"}{.involvedObject.name}{"\t"}{.source.component}{"\t"}{.reportingController}{"\n"}{end}'
  fi

  return 0
}

run_cleanup_with_deadline() {
  local failure_deadline="$1"
  local run_seconds
  shift

  if ! run_seconds="$(deadline_run_seconds "${failure_deadline}" 0 "${failure_handling_budget_seconds}")"; then
    return 124
  fi
  timeout --signal=TERM --kill-after="${failure_kill_grace_seconds}" "${run_seconds}s" "$@"
}

cleanup() {
  local proof_status="$1"
  local cleanup_status=0
  local next_cleanup_status=0
  local failure_deadline=$((SECONDS + failure_handling_budget_seconds))

  trap - EXIT
  if [ "${proof_status}" -ne 0 ]; then
    capture_failure_diagnostics "${proof_status}" "${failure_deadline}" || true
  fi

  run_cleanup_with_deadline "${failure_deadline}" bash ./scripts/local/delete-k3d-cluster.sh || cleanup_status=$?
  run_cleanup_with_deadline "${failure_deadline}" rm -rf "${tmp}" || next_cleanup_status=$?
  if [ "${cleanup_status}" -eq 0 ] && [ "${next_cleanup_status}" -ne 0 ]; then
    cleanup_status="${next_cleanup_status}"
  fi

  if [ "${cleanup_status}" -ne 0 ]; then
    echo "❌ k3d proof cleanup failed with exit ${cleanup_status}" >&2
  fi

  # A diagnostic or cleanup failure must never relabel the proof failure.
  if [ "${proof_status}" -ne 0 ]; then
    exit "${proof_status}"
  fi
  if [ "${cleanup_status}" -ne 0 ]; then
    exit "${cleanup_status}"
  fi
  exit "${proof_status}"
}

trap 'cleanup "$?"' EXIT

bash ./scripts/local/create-k3d-cluster.sh
helm dependency build chart

# Standard-channel Gateway API CRDs (Gateway/GatewayClass/HTTPRoute) deploy separately from kgateway-crds.
# Vendored + checksum-pinned (RB-244): the frozen v1.6.0 release URL upstream
# renamed standard-channel.yaml to standard-install.yaml and began 404-ing. The
# manifest is now applied from a local fixture after fail-closed SHA-256
# verification, so the proof never depends on a live, renameable external URL.
gateway_crds="$(bash ./scripts/local/gateway-api-crd-fixture.sh verify)"
kubectl --context "k3d-${cluster_name}" apply -f "${gateway_crds}"
# The rendered fallback applies server-side (stable field manager): the archive's
# GatewayParameters CRD exceeds the 262144-byte last-applied-configuration
# annotation that client-side apply would persist, so only server-side apply
# installs it. The primary archive apply stays client-side.
kubectl --context "k3d-${cluster_name}" apply -f chart/charts/kgateway-crds-v2.2.9.tgz 2>/dev/null || helm template kgateway-crds chart/charts/kgateway-crds-v2.2.9.tgz | kubectl --context "k3d-${cluster_name}" apply --server-side --field-manager=platinum-k3d-proof -f -

# Install platinum with the kgateway control plane + CRDs enabled.
helm upgrade --install --kube-context "k3d-${cluster_name}" platinum chart --namespace sulfoxide --create-namespace \
  --values chart/values.example.yaml --values chart/values.lapras.yaml \
  --set upstream.enabled=true --set kgatewayCrds.enabled=false \
  --wait --timeout "${helm_readiness_timeout_seconds}s"

# The shared Gateway must reach Programmed=True with kgateway accepting the GatewayClass.
kubectl --context "k3d-${cluster_name}" --namespace sulfoxide wait --for=condition=Programmed gateway/platinum-gateway --timeout="${gateway_readiness_timeout_seconds}s"

# Wait for real proxy endpoints, then require a reachable LoadBalancer ingress or the
# k3d host endpoint. The selected endpoint must answer /healthz with HTTP 2xx.
endpoint=""
http_status=""
health_deadline=$((SECONDS + health_readiness_timeout_seconds))
while ((SECONDS < health_deadline)); do
  if ! request_timeout_seconds="$(bounded_health_request_seconds "${health_deadline}")"; then
    break
  fi
  endpoint_ips="$(kubectl --context "k3d-${cluster_name}" --namespace sulfoxide get endpoints platinum-edge --request-timeout="${request_timeout_seconds}s" -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null || true)"
  if [ -n "${endpoint_ips}" ]; then
    if ! request_timeout_seconds="$(bounded_health_request_seconds "${health_deadline}")"; then
      break
    fi
    ingress_host="$(kubectl --context "k3d-${cluster_name}" --namespace sulfoxide get service platinum-edge --request-timeout="${request_timeout_seconds}s" -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)"
    if [ -z "${ingress_host}" ]; then
      if ! request_timeout_seconds="$(bounded_health_request_seconds "${health_deadline}")"; then
        break
      fi
      ingress_host="$(kubectl --context "k3d-${cluster_name}" --namespace sulfoxide get service platinum-edge --request-timeout="${request_timeout_seconds}s" -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)"
    fi
    if [ -n "${ingress_host}" ]; then
      endpoint="http://${ingress_host}:80"
      if ! request_timeout_seconds="$(bounded_health_request_seconds "${health_deadline}")"; then
        break
      fi
      connect_timeout_seconds="${request_timeout_seconds}"
      ((connect_timeout_seconds > 2)) && connect_timeout_seconds=2
      http_status="$(curl --connect-timeout "${connect_timeout_seconds}" --max-time "${request_timeout_seconds}" -sS -o /dev/null -w '%{http_code}' "${endpoint}/healthz" || true)"
    fi
    if [[ ! ${http_status} =~ ^2[0-9][0-9]$ ]]; then
      endpoint="http://127.0.0.1:${http_port}"
      if ! request_timeout_seconds="$(bounded_health_request_seconds "${health_deadline}")"; then
        break
      fi
      connect_timeout_seconds="${request_timeout_seconds}"
      ((connect_timeout_seconds > 2)) && connect_timeout_seconds=2
      http_status="$(curl --connect-timeout "${connect_timeout_seconds}" --max-time "${request_timeout_seconds}" -sS -o /dev/null -w '%{http_code}' "${endpoint}/healthz" || true)"
    fi
    [[ ${http_status} =~ ^2[0-9][0-9]$ ]] && break
  fi
  sleep_seconds=$((health_deadline - SECONDS))
  ((sleep_seconds > 2)) && sleep_seconds=2
  ((sleep_seconds > 0)) && sleep "${sleep_seconds}"
done
[ -z "${endpoint}" ] && echo "❌ no LoadBalancer ingress or k3d local endpoint became available" >&2 && exit 1
[[ ! ${http_status} =~ ^2[0-9][0-9]$ ]] && echo "❌ ${endpoint}/healthz did not return HTTP 2xx (last status: ${http_status:-none})" >&2 && exit 1

# Local OCI round-trip.
PUBLISH_MODE=oci PUBLISH_DRY_RUN=false RELEASE_VERSION=v0.1.0 PUBLISH_OUTPUT_DIR="${tmp}/oci" OCI_REGISTRY="localhost:${registry_port}" OCI_REPOSITORY=charts OCI_PLAIN_HTTP=true bash ./scripts/ci/publish.sh
helm pull "oci://localhost:${registry_port}/charts/platinum" --version 0.1.0 --plain-http --destination "${tmp}"
test -s "${tmp}/platinum-0.1.0.tgz"
cp "${tmp}/platinum-0.1.0.tgz" "${archive_path}"
sha256sum "${archive_path}" >"${archive_sha_path}"
test -s "${archive_path}"
test -s "${archive_sha_path}"

echo "✅ k3d install, Gateway Programmed, health 2xx, and local OCI round-trip passed; archive=${archive_path} sha256=${archive_sha_path}"
