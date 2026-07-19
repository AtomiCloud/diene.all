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

cleanup() {
  local proof_status="$1"
  local cleanup_status=0

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
gateway_crds="${GATEWAY_API_CRDS:-https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.6.0/standard-channel.yaml}"
kubectl --context "k3d-${cluster_name}" apply -f "${gateway_crds}"
kubectl --context "k3d-${cluster_name}" apply -f chart/charts/kgateway-crds-v2.2.9.tgz 2>/dev/null || helm template kgateway-crds chart/charts/kgateway-crds-v2.2.9.tgz | kubectl --context "k3d-${cluster_name}" apply -f -

# Install platinum with the kgateway control plane + CRDs enabled.
helm upgrade --install platinum chart --namespace sulfoxide --create-namespace \
  --values chart/values.example.yaml --values chart/values.lapras.yaml \
  --set upstream.enabled=true --set kgatewayCrds.enabled=false \
  --wait --timeout 5m

# The shared Gateway must reach Programmed=True with kgateway accepting the GatewayClass.
kubectl --context "k3d-${cluster_name}" --namespace sulfoxide wait --for=condition=Programmed gateway/platinum-gateway --timeout=5m

# Wait for real proxy endpoints, then require a reachable LoadBalancer ingress or the
# k3d host endpoint. The selected endpoint must answer /healthz with HTTP 2xx.
endpoint=""
http_status=""
for _attempt in $(seq 1 120); do
  endpoint_ips="$(kubectl --context "k3d-${cluster_name}" --namespace sulfoxide get endpoints platinum-edge -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null || true)"
  if [ -n "${endpoint_ips}" ]; then
    ingress_host="$(kubectl --context "k3d-${cluster_name}" --namespace sulfoxide get service platinum-edge -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)"
    [ -z "${ingress_host}" ] && ingress_host="$(kubectl --context "k3d-${cluster_name}" --namespace sulfoxide get service platinum-edge -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)"
    if [ -n "${ingress_host}" ]; then
      endpoint="http://${ingress_host}:80"
      http_status="$(curl --connect-timeout 2 --max-time 5 -sS -o /dev/null -w '%{http_code}' "${endpoint}/healthz" || true)"
    fi
    if [[ ! ${http_status} =~ ^2[0-9][0-9]$ ]]; then
      endpoint="http://127.0.0.1:${http_port}"
      http_status="$(curl --connect-timeout 2 --max-time 5 -sS -o /dev/null -w '%{http_code}' "${endpoint}/healthz" || true)"
    fi
    [[ ${http_status} =~ ^2[0-9][0-9]$ ]] && break
  fi
  sleep 2
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
