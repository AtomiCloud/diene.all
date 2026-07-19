#!/usr/bin/env bash
# ### aluminium-k3d-proof
# #### source: aluminium
# RESERVED serialized proof (not run in the unit tier): install the aluminium
# chart on an invocation-owned k3d cluster, prove collector readiness and real
# OTLP/HTTP protobuf acceptance, then round-trip the OCI chart artifact.
set -euo pipefail

isolate_by_path="${K3D_ISOLATE_BY_PATH:-}"
artifact_root="${ALUMINIUM_K3D_ARTIFACT_DIR:-/home/kirin/.kteam/mrrm2rhw-7c3a63dd/evidence/aluminium-k3d}"
namespace="${NAMESPACE:-telemetry}"
run_nonce="${K3D_RUN_NONCE:-$(date -u +%Y%m%dT%H%M%SZ)-$$}"

[ "${isolate_by_path}" != "true" ] && echo "❌ K3D_ISOLATE_BY_PATH=true is mandatory" >&2 && exit 1

path_key="$(printf '%s' "${PWD}" | sha256sum | cut -c1-8)"
isolation_key="$(printf '%s:%s' "${PWD}" "${run_nonce}" | sha256sum | cut -c1-12)"
run_stamp="$(date -u +%Y%m%dT%H%M%SZ)"
artifact_dir="${artifact_root}/${run_stamp}-${isolation_key}"
run_log="${artifact_dir}/run.log"
cleanup_log="${artifact_dir}/cleanup.log"

mkdir -p "${artifact_dir}"
exec > >(tee -a "${run_log}") 2>&1

export K3D_CLUSTER_NAME="diene-aluminium-${path_key}-${isolation_key:0:6}"
export K3D_REGISTRY_NAME="diene-aluminium-registry-${path_key}-${isolation_key:0:6}"
export K3D_REGISTRY_PORT="$((20000 + (16#${isolation_key:0:4} % 10000)))"
export K3D_HTTP_PORT="$((30000 + (16#${isolation_key:4:4} % 10000)))"

cluster_name="${K3D_CLUSTER_NAME}"
registry_name="${K3D_REGISTRY_NAME}"
registry_port="${K3D_REGISTRY_PORT}"
kube_context="k3d-${cluster_name}"
cluster_cleanup_eligible=false
registry_cleanup_eligible=false
cluster_created=false
registry_created=false
port_forward_pid=""
result=0
cleanup_result=0
final_result=0

capture_diagnostics() {
  local kubectl_args=(--context "${kube_context}" --request-timeout=15s --namespace "${namespace}")
  date -u +%Y-%m-%dT%H:%M:%SZ >"${artifact_dir}/diagnostics-captured-at.txt"
  kubectl "${kubectl_args[@]}" \
    get pods -o wide >"${artifact_dir}/pods.txt" 2>&1
  kubectl "${kubectl_args[@]}" \
    describe pods >"${artifact_dir}/pods-describe.txt" 2>&1
  kubectl "${kubectl_args[@]}" \
    get alloy -o yaml >"${artifact_dir}/alloy-status.yaml" 2>&1
  kubectl "${kubectl_args[@]}" \
    describe alloy/aluminium-alloy-metrics alloy/aluminium-alloy-logs >"${artifact_dir}/alloy-describe.txt" 2>&1
  kubectl "${kubectl_args[@]}" \
    get deployments,statefulsets,daemonsets,jobs,services -o wide >"${artifact_dir}/workloads.txt" 2>&1
  kubectl "${kubectl_args[@]}" \
    get events --sort-by=.lastTimestamp >"${artifact_dir}/events.txt" 2>&1
  kubectl "${kubectl_args[@]}" \
    logs deployment/aluminium-alloy-operator --all-containers --tail=500 >"${artifact_dir}/alloy-operator.log" 2>&1
  kubectl "${kubectl_args[@]}" \
    logs statefulset/aluminium-alloy-metrics --all-containers --tail=500 >"${artifact_dir}/alloy-metrics.log" 2>&1
  kubectl "${kubectl_args[@]}" \
    logs daemonset/aluminium-alloy-logs --all-containers --tail=500 >"${artifact_dir}/alloy-logs.log" 2>&1
}

trap '
  result=$?
  cleanup_result=0
  set +e
  if [ -n "${port_forward_pid}" ]; then
    kill "${port_forward_pid}" 2>/dev/null
    wait "${port_forward_pid}" 2>/dev/null
  fi
  if [ "${cluster_cleanup_eligible}" = "true" ]; then
    capture_diagnostics
  fi
  K3D_DELETE_CLUSTER="${cluster_cleanup_eligible}" \
    K3D_DELETE_REGISTRY="${registry_cleanup_eligible}" \
    K3D_CLUSTER_NAME="${cluster_name}" \
    K3D_REGISTRY_NAME="${registry_name}" \
    bash ./scripts/local/delete-k3d-cluster.sh >>"${cleanup_log}" 2>&1 || cleanup_result=$?
  final_result="${result}"
  if [ "${final_result}" -eq 0 ] && [ "${cleanup_result}" -ne 0 ]; then
    final_result="${cleanup_result}"
  fi
  printf "exit_code=%s\nproof_exit_code=%s\ncleanup_exit_code=%s\ncluster_created=%s\nregistry_created=%s\n" \
    "${final_result}" "${result}" "${cleanup_result}" "${cluster_created}" "${registry_created}" \
    >"${artifact_dir}/result.env"
  if [ "${final_result}" -eq 0 ]; then
    echo "✅ aluminium k3d readiness, OTLP trace/log acceptance, OCI round-trip, and cleanup passed"
  else
    echo "❌ aluminium k3d proof or owned-resource cleanup failed; evidence: ${artifact_dir}" >&2
  fi
  exit "${final_result}"
' EXIT

printf 'worktree=%s\nhead=%s\ntree=%s\npath_key=%s\nisolation_key=%s\ncluster=%s\nregistry=%s\nregistry_port=%s\nhttp_port=%s\nkube_context=%s\nnamespace=%s\n' \
  "${PWD}" "$(git rev-parse HEAD)" "$(git rev-parse 'HEAD^{tree}')" "${path_key}" "${isolation_key}" \
  "${cluster_name}" "${registry_name}" "${registry_port}" "${K3D_HTTP_PORT}" "${kube_context}" "${namespace}" \
  >"${artifact_dir}/invocation.env"

if k3d cluster list --no-headers | awk -v name="${cluster_name}" '$1 == name { found = 1 } END { exit !found }'; then
  echo "❌ isolated cluster name already exists: ${cluster_name}" >&2
  exit 1
fi
if k3d registry list --no-headers | awk -v name="${registry_name}" '$1 == name || $1 == "k3d-" name { found = 1 } END { exit !found }'; then
  echo "❌ isolated registry name already exists: ${registry_name}" >&2
  exit 1
fi

# The unique names were absent before the provisioning attempt. Cleanup may
# therefore remove only resources appearing under those reserved names, even
# when k3d fails partway through creation.
cluster_cleanup_eligible=true
registry_cleanup_eligible=true
bash ./scripts/local/create-k3d-cluster.sh
cluster_created=true
registry_created=true

helm dependency build chart | tee "${artifact_dir}/helm-dependency-build.log"
helm upgrade --install aluminium chart \
  --kube-context "${kube_context}" \
  --namespace "${namespace}" \
  --create-namespace \
  --values chart/values.example.yaml \
  --values chart/values.lapras.yaml \
  --wait \
  --timeout 5m | tee "${artifact_dir}/helm-install.log"

kubectl --context "${kube_context}" --namespace "${namespace}" \
  wait --for=condition=Available deployment/aluminium-alloy-operator --timeout=5m
kubectl --context "${kube_context}" --namespace "${namespace}" \
  wait --for=condition=Deployed alloy/aluminium-alloy-metrics --timeout=5m
kubectl --context "${kube_context}" --namespace "${namespace}" \
  wait --for=condition=Deployed alloy/aluminium-alloy-logs --timeout=5m
kubectl --context "${kube_context}" --namespace "${namespace}" \
  rollout status statefulset/aluminium-alloy-metrics --timeout=5m
kubectl --context "${kube_context}" --namespace "${namespace}" \
  rollout status daemonset/aluminium-alloy-logs --timeout=5m

kubectl --context "${kube_context}" --namespace "${namespace}" get alloy -o json \
  >"${artifact_dir}/alloy-status.json"
jq -e '
  [.items[] |
    select(.metadata.name == "aluminium-alloy-metrics" or
           .metadata.name == "aluminium-alloy-logs")] as $alloys |
  ($alloys | length == 2) and
  ($alloys | all(.[];
    any(.status.conditions[]?;
      .type == "Deployed" and .status == "True")))
' "${artifact_dir}/alloy-status.json" >/dev/null

kubectl --context "${kube_context}" --namespace "${namespace}" get service -o json \
  >"${artifact_dir}/services.json"
receiver_service="$(jq -er '
  [.items[] |
    select(any(.spec.ports[]?;
      .name == "otlp-http" and .port == 4318))] |
  if length == 1 then .[0].metadata.name
  else error("expected exactly one OTLP/HTTP receiver service")
  end
' "${artifact_dir}/services.json")"
printf '%s\n' "${receiver_service}" >"${artifact_dir}/receiver-service.txt"
kubectl --context "${kube_context}" --namespace "${namespace}" \
  get "service/${receiver_service}" -o yaml >"${artifact_dir}/receiver-service.yaml"

kubectl --context "${kube_context}" --namespace "${namespace}" \
  port-forward --address 127.0.0.1 "service/${receiver_service}" :4318 \
  >"${artifact_dir}/port-forward.log" 2>&1 &
port_forward_pid=$!
local_otlp_port=""
for _ in $(seq 1 60); do
  if ! kill -0 "${port_forward_pid}" 2>/dev/null; then
    wait "${port_forward_pid}"
    echo "❌ OTLP receiver port-forward exited before becoming ready" >&2
    exit 1
  fi
  local_otlp_port="$(sed -n 's/^Forwarding from 127\.0\.0\.1:\([0-9][0-9]*\) -> 4318$/\1/p' "${artifact_dir}/port-forward.log" | head -n 1)"
  [ -n "${local_otlp_port}" ] && break
  sleep 1
done
[ -z "${local_otlp_port}" ] && echo "❌ OTLP receiver port-forward did not become ready" >&2 && exit 1
printf '%s\n' "${local_otlp_port}" >"${artifact_dir}/receiver-local-port.txt"

# Valid OTLP protobuf requests containing one named span and one INFO log.
printf '%s' 'Ck4STBJKChABAgMEBQYHCAkKCwwNDg8QEggBAgMEBQYHCCoYYWx1bWluaXVtLWszZC1wcm9vZi1zcGFuMAE5AEBTbuaU4xdBQIJibuaU4xc=' |
  base64 --decode >"${artifact_dir}/otlp-traces.pb"
printf '%s' 'ClUSUxJRCQBAU27mlOMXEAkaBElORk8qGQoXYWx1bWluaXVtIGszZCBwcm9vZiBsb2dKEAECAwQFBgcICQoLDA0ODxBSCAECAwQFBgcIWQBAU27mlOMX' |
  base64 --decode >"${artifact_dir}/otlp-logs.pb"

trace_http_code="$(curl --silent --show-error \
  --connect-timeout 5 \
  --max-time 30 \
  --output "${artifact_dir}/otlp-traces-response.pb" \
  --write-out '%{http_code}' \
  --request POST \
  --header 'Content-Type: application/x-protobuf' \
  --data-binary "@${artifact_dir}/otlp-traces.pb" \
  "http://127.0.0.1:${local_otlp_port}/v1/traces")"
printf '%s\n' "${trace_http_code}" >"${artifact_dir}/otlp-traces-http-code.txt"
[ "${trace_http_code}" != "200" ] && echo "❌ OTLP trace request returned HTTP ${trace_http_code}" >&2 && exit 1

logs_http_code="$(curl --silent --show-error \
  --connect-timeout 5 \
  --max-time 30 \
  --output "${artifact_dir}/otlp-logs-response.pb" \
  --write-out '%{http_code}' \
  --request POST \
  --header 'Content-Type: application/x-protobuf' \
  --data-binary "@${artifact_dir}/otlp-logs.pb" \
  "http://127.0.0.1:${local_otlp_port}/v1/logs")"
printf '%s\n' "${logs_http_code}" >"${artifact_dir}/otlp-logs-http-code.txt"
[ "${logs_http_code}" != "200" ] && echo "❌ OTLP log request returned HTTP ${logs_http_code}" >&2 && exit 1

mkdir -p "${artifact_dir}/oci-package" "${artifact_dir}/oci-pull"
PUBLISH_MODE=oci \
  PUBLISH_DRY_RUN=false \
  RELEASE_VERSION=v0.1.0 \
  PUBLISH_OUTPUT_DIR="${artifact_dir}/oci-package" \
  OCI_REGISTRY="localhost:${registry_port}" \
  OCI_REPOSITORY=charts \
  OCI_PLAIN_HTTP=true \
  bash ./scripts/ci/publish.sh | tee "${artifact_dir}/oci-push.log"
helm pull "oci://localhost:${registry_port}/charts/diene-charts-aluminium" \
  --version 0.1.0 \
  --plain-http \
  --destination "${artifact_dir}/oci-pull" | tee "${artifact_dir}/oci-pull.log"
oci_package="${artifact_dir}/oci-pull/diene-charts-aluminium-0.1.0.tgz"
test -s "${oci_package}"
sha256sum "${oci_package}" >"${artifact_dir}/oci-package.sha256"
helm show chart "${oci_package}" >"${artifact_dir}/oci-chart.yaml"

printf 'status=passed\ntrace_http_code=%s\nlogs_http_code=%s\nreceiver_service=%s\n' \
  "${trace_http_code}" "${logs_http_code}" "${receiver_service}" >"${artifact_dir}/proof.env"
