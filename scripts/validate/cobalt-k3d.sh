#!/usr/bin/env bash
set -euo pipefail

# cobalt integration tier (reserved for orchestration-authorized proof). Installs
# the chart on an ephemeral k3d cluster, asserts ESO pods are healthy and the
# SoS ClusterSecretStore is applied (Ready needs a live Infisical endpoint, which
# k3d does not provide, so the assertion is applied + schema-valid, not Ready),
# then proves an OCI push/pull round-trip. The caller supplies absolute durable
# evidence/package paths; the reserved handoff owns tee + hashes before cleanup.

[ "${K3D_ISOLATE_BY_PATH:-}" = "true" ] || {
  echo "❌ K3D_ISOLATE_BY_PATH=true is mandatory for the cobalt proof" >&2
  exit 1
}
package_path="${COBALT_K3D_PACKAGE_PATH:?set COBALT_K3D_PACKAGE_PATH to an absolute durable .tgz path}"
[ "${package_path#/}" != "${package_path}" ] || {
  echo "❌ COBALT_K3D_PACKAGE_PATH must be absolute" >&2
  exit 1
}
if [ "${COBALT_K3D_DEFER_CLEANUP:-false}" = "true" ] && [ -z "${K3D_OWNERSHIP_MARKER:-}" ]; then
  echo "❌ deferred cleanup requires an explicit absolute K3D_OWNERSHIP_MARKER" >&2
  exit 1
fi

isolation_key="$(printf '%s' "${PWD}" | sha256sum | cut -c1-8)"
export K3D_CLUSTER_NAME="${K3D_CLUSTER_NAME:-diene-cobalt-${isolation_key}}"
export K3D_REGISTRY_NAME="${K3D_REGISTRY_NAME:-diene-cobalt-registry-${isolation_key}}"
export K3D_REGISTRY_PORT="${K3D_REGISTRY_PORT:-$((20000 + (16#${isolation_key:0:4} % 10000)))}"
export K3D_HTTP_PORT="${K3D_HTTP_PORT:-$((30000 + (16#${isolation_key:4:4} % 10000)))}"

cluster_name="${K3D_CLUSTER_NAME}"
registry_port="${K3D_REGISTRY_PORT:-5001}"
namespace="${NAMESPACE:-external-secrets}"
release="${RELEASE:-cobalt}"
tmp="$(mktemp -d)"
export K3D_OWNER_ID="${K3D_OWNER_ID:-cobalt-${isolation_key}-$$}"
export K3D_OWNERSHIP_MARKER="${K3D_OWNERSHIP_MARKER:-${tmp}/k3d-owner}"
cleanup() {
  status=$?
  if [ "${COBALT_K3D_DEFER_CLEANUP:-false}" != "true" ] && [ -e "${K3D_OWNERSHIP_MARKER}" ]; then
    bash ./scripts/local/delete-k3d-cluster.sh >/dev/null 2>&1 || status=1
  fi
  rm -rf "${tmp}"
  exit "${status}"
}
trap cleanup EXIT

bash ./scripts/local/create-k3d-cluster.sh
helm dependency build chart
helm upgrade --install "${release}" chart --namespace "${namespace}" --create-namespace \
  --values chart/values.example.yaml --values chart/values.lapras.yaml --wait --timeout 5m
kubectl --context "k3d-${cluster_name}" --namespace "${namespace}" wait \
  --for=condition=Available deployment/cobalt-eso --timeout=5m
kubectl --context "k3d-${cluster_name}" --namespace "${namespace}" get pods \
  -l app.kubernetes.io/instance="${release}" -o json |
  jq -e '[.items[] | select(.metadata.labels["batch.kubernetes.io/job-name"] == null)] | length > 0 and all(.[]; .status.phase == "Running")' >/dev/null
# The SoS ClusterSecretStore is applied server-side and validated by the ESO CRD
# webhook; Ready is not asserted (no live Infisical on k3d).
kubectl --context "k3d-${cluster_name}" get clustersecretstore cobalt-sos -o json |
  jq -e '.apiVersion == "external-secrets.io/v1" and .metadata.name == "cobalt-sos"' >/dev/null

PUBLISH_MODE=oci PUBLISH_DRY_RUN=false RELEASE_VERSION=v0.1.0 PUBLISH_OUTPUT_DIR="${tmp}/oci" \
  OCI_REGISTRY="localhost:${registry_port}" OCI_REPOSITORY=charts OCI_PLAIN_HTTP=true \
  bash ./scripts/ci/publish.sh
helm pull "oci://localhost:${registry_port}/charts/diene-cobalt" --version 0.1.0 --plain-http --destination "${tmp}"
test -s "${tmp}/diene-cobalt-0.1.0.tgz"
mkdir -p "$(dirname "${package_path}")"
cp "${tmp}/diene-cobalt-0.1.0.tgz" "${package_path}"
test -s "${package_path}"

echo "✅ k3d lapras install, ESO pod health, store applied, and local OCI round-trip passed"
