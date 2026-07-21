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

capture_failure_diagnostics() {
  local proof_status="$1"
  local failure_deadline="$2"
  local diagnostics_dir="${evidence_dir}/failure-diagnostics"

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
  # environment, command arguments, event messages, descriptions, or logs are
  # captured. stderr is discarded and every whole-line TSV file is byte-capped.
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
    -o 'jsonpath={range .items[*]}{.metadata.namespace}{"\t"}{.metadata.name}{"\t"}{.status.phase}{"\t"}{range .status.conditions[*]}{.type}{"="}{.status}{":"}{.reason}{","}{end}{"\t"}{range .status.containerStatuses[*]}{.name}{":ready="}{.ready}{":restarts="}{.restartCount}{":waiting="}{.state.waiting.reason}{":terminated="}{.state.terminated.reason}{":exit="}{.state.terminated.exitCode}{","}{end}{"\n"}{end}'
  capture_diagnostic_file "${failure_deadline}" "${diagnostics_dir}/gateway.tsv" \
    kubectl --context "k3d-${cluster_name}" --namespace sulfoxide --request-timeout=15s \
    get gateway platinum-gateway \
    -o 'jsonpath={.kind}{"\t"}{.metadata.namespace}{"\t"}{.metadata.name}{"\t"}{.metadata.generation}{"\t"}{.status.observedGeneration}{"\t"}{range .status.conditions[*]}{.type}{"="}{.status}{":"}{.reason}{","}{end}{"\t"}{range .status.listeners[*]}{.name}{":routes="}{.attachedRoutes}{":"}{range .conditions[*]}{.type}{"="}{.status}{":"}{.reason}{","}{end}{";"}{end}{"\n"}'
  capture_diagnostic_file "${failure_deadline}" "${diagnostics_dir}/gateway-events.tsv" \
    kubectl --context "k3d-${cluster_name}" --namespace sulfoxide --request-timeout=15s \
    get events --field-selector involvedObject.kind=Gateway,involvedObject.name=platinum-gateway \
    -o 'jsonpath={range .items[*]}{.type}{"\t"}{.reason}{"\t"}{.count}{"\t"}{.eventTime}{"\t"}{.lastTimestamp}{"\t"}{.involvedObject.kind}{"\t"}{.involvedObject.name}{"\t"}{.source.component}{"\t"}{.reportingController}{"\n"}{end}'

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
