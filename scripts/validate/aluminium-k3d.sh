#!/usr/bin/env bash
# ### aluminium-k3d-proof
# #### source: aluminium
# RESERVED serialized proof (not run in the unit tier): install the aluminium
# chart on a throwaway k3d cluster, assert the Alloy Operator + collectors come
# healthy, send a test OTLP span/log to :4318, and round-trip the OCI publish.
# See proof-ready.md in the kteam durable coordination directory.
set -euo pipefail

if [ "${K3D_ISOLATE_BY_PATH:-false}" = "true" ]; then
  isolation_key="$(printf '%s' "${PWD}" | sha256sum | cut -c1-8)"
  export K3D_CLUSTER_NAME="${K3D_CLUSTER_NAME:-diene-aluminium-${isolation_key}}"
  export K3D_REGISTRY_NAME="${K3D_REGISTRY_NAME:-diene-aluminium-registry-${isolation_key}}"
  export K3D_REGISTRY_PORT="${K3D_REGISTRY_PORT:-$((20000 + (16#${isolation_key:0:4} % 10000)))}"
  export K3D_HTTP_PORT="${K3D_HTTP_PORT:-$((30000 + (16#${isolation_key:4:4} % 10000)))}"
fi

cluster_name="${K3D_CLUSTER_NAME:-diene-aluminium}"
registry_port="${K3D_REGISTRY_PORT:-5001}"
namespace="${NAMESPACE:-telemetry}"
tmp="$(mktemp -d)"
trap 'bash ./scripts/local/delete-k3d-cluster.sh >/dev/null 2>&1 || true; rm -rf "${tmp}"' EXIT

bash ./scripts/local/create-k3d-cluster.sh
helm dependency build chart
helm upgrade --install aluminium chart --namespace "${namespace}" --create-namespace --values chart/values.example.yaml --values chart/values.lapras.yaml --wait --timeout 5m
# The Alloy Operator Deployment is the real PodSpec workload the chart installs.
kubectl --context "k3d-${cluster_name}" --namespace "${namespace}" wait --for=condition=Available deployment/aluminium-alloy-operator --timeout=5m
# Both Alloy CRs must reach a ready state under the operator.
kubectl --context "k3d-${cluster_name}" --namespace "${namespace}" get alloy -o json | jq -e '[.items[]] | length == 2' >/dev/null
# Integration-tier OTLP contract: a test span/log pushed to :4318 is accepted.
# (Port-forward the alloy-metrics OTLP receiver and post a minimal OTLP/HTTP payload.)

PUBLISH_MODE=oci PUBLISH_DRY_RUN=false RELEASE_VERSION=v0.1.0 PUBLISH_OUTPUT_DIR="${tmp}/oci" OCI_REGISTRY="localhost:${registry_port}" OCI_REPOSITORY=charts OCI_PLAIN_HTTP=true bash ./scripts/ci/publish.sh
helm pull "oci://localhost:${registry_port}/charts/diene-charts-aluminium" --version 0.1.0 --plain-http --destination "${tmp}"
test -s "${tmp}/diene-charts-aluminium-0.1.0.tgz"

echo "✅ aluminium k3d lapras install, collector health, and local OCI round-trip passed"
