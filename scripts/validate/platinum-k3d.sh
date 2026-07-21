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
# Gateway Programmed 600 + endpoint/health readiness 300 + 300 for bounded
# pre-teardown diagnostics and cleanup = 2100 total worst case. This leaves
# 5100 seconds for the existing non-binding cluster/CRD/OCI work inside the
# unchanged 7200-second shard hard timeout.
readonly helm_readiness_timeout_seconds=900
readonly gateway_readiness_timeout_seconds=600
readonly health_readiness_timeout_seconds=300
readonly proof_overhead_budget_seconds=300
readonly total_worst_case_budget_seconds=2100
readonly shard_hard_timeout_seconds=7200

if ((total_worst_case_budget_seconds != helm_readiness_timeout_seconds + gateway_readiness_timeout_seconds + health_readiness_timeout_seconds + proof_overhead_budget_seconds)); then
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

capture_diagnostic_file() {
  local max_seconds="$1"
  local output_path="$2"
  shift 2

  timeout --signal=TERM --kill-after=2 "${max_seconds}s" "$@" >"${output_path}" 2>&1 || true
}

capture_failure_diagnostics() {
  local proof_status="$1"
  local diagnostics_dir="${evidence_dir}/failure-diagnostics"

  mkdir -p "${diagnostics_dir}" || {
    echo "⚠️ unable to create Platinum failure diagnostics directory" >&2
    return 0
  }

  {
    printf 'proof_exit_status=%s\n' "${proof_status}"
    printf 'captured_at_utc=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf 'cluster_context=k3d-%s\n' "${cluster_name}"
  } >"${diagnostics_dir}/metadata.txt" 2>&1 || true

  # Each collection is independently capped. Even if every command reaches its
  # cap, diagnostics use at most 260 seconds of the 300-second overhead budget.
  capture_diagnostic_file 20 "${diagnostics_dir}/helm-status.txt" \
    helm status platinum --kube-context "k3d-${cluster_name}" --namespace sulfoxide
  capture_diagnostic_file 20 "${diagnostics_dir}/helm-history.txt" \
    helm history platinum --kube-context "k3d-${cluster_name}" --namespace sulfoxide
  capture_diagnostic_file 20 "${diagnostics_dir}/node-state.txt" \
    kubectl --context "k3d-${cluster_name}" --request-timeout=20s get nodes -o wide
  capture_diagnostic_file 20 "${diagnostics_dir}/node-descriptions.txt" \
    kubectl --context "k3d-${cluster_name}" --request-timeout=20s describe nodes
  capture_diagnostic_file 20 "${diagnostics_dir}/workload-state.txt" \
    kubectl --context "k3d-${cluster_name}" --request-timeout=20s get pods,deployments,statefulsets,daemonsets,jobs,replicasets,services,endpoints -A -o wide
  capture_diagnostic_file 20 "${diagnostics_dir}/gateway-state.txt" \
    kubectl --context "k3d-${cluster_name}" --request-timeout=20s get gatewayclasses,gateways,httproutes -A -o wide
  capture_diagnostic_file 20 "${diagnostics_dir}/pod-descriptions.txt" \
    kubectl --context "k3d-${cluster_name}" --request-timeout=20s describe pods -A
  capture_diagnostic_file 20 "${diagnostics_dir}/workload-descriptions.txt" \
    kubectl --context "k3d-${cluster_name}" --request-timeout=20s describe deployments,statefulsets,daemonsets,jobs -A
  capture_diagnostic_file 20 "${diagnostics_dir}/events.txt" \
    kubectl --context "k3d-${cluster_name}" --request-timeout=20s get events -A --sort-by=.lastTimestamp
  capture_diagnostic_file 40 "${diagnostics_dir}/pod-logs.txt" \
    kubectl --context "k3d-${cluster_name}" --namespace sulfoxide --request-timeout=40s logs \
    -l app.kubernetes.io/instance=platinum --all-containers=true --prefix=true --tail=500 --max-log-requests=20
  capture_diagnostic_file 40 "${diagnostics_dir}/pod-logs-previous.txt" \
    kubectl --context "k3d-${cluster_name}" --namespace sulfoxide --request-timeout=40s logs \
    -l app.kubernetes.io/instance=platinum --all-containers=true --prefix=true --previous --tail=500 --max-log-requests=20

  return 0
}

cleanup() {
  local proof_status="$1"
  local cleanup_status=0

  trap - EXIT
  if [ "${proof_status}" -ne 0 ]; then
    capture_failure_diagnostics "${proof_status}" || true
  fi

  bash ./scripts/local/delete-k3d-cluster.sh || cleanup_status=$?
  rm -rf "${tmp}" || cleanup_status=$?

  if [ "${cleanup_status}" -ne 0 ]; then
    echo "❌ k3d proof cleanup failed with exit ${cleanup_status}" >&2
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
