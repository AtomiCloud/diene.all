#!/usr/bin/env bash
set -euo pipefail

[ "${K3D_ISOLATE_BY_PATH:-}" = "true" ] || {
  echo "❌ K3D_ISOLATE_BY_PATH=true is mandatory for the Carbon proof" >&2
  exit 1
}

isolation_key="$(printf '%s' "${PWD}" | sha256sum | cut -c1-8)"
export K3D_CLUSTER_NAME="${K3D_CLUSTER_NAME:-diene-carbon-${isolation_key}}"
export K3D_REGISTRY_NAME="${K3D_REGISTRY_NAME:-diene-carbon-registry-${isolation_key}}"
export K3D_REGISTRY_PORT="${K3D_REGISTRY_PORT:-$((20000 + (16#${isolation_key:0:4} % 10000)))}"
export K3D_HTTP_PORT="${K3D_HTTP_PORT:-$((30000 + (16#${isolation_key:4:4} % 10000)))}"
export K3D_OWNER_ID="${K3D_OWNER_ID:-carbon-${isolation_key}-$$}"

tmp="$(mktemp -d)"
export K3D_OWNERSHIP_MARKER="${K3D_OWNERSHIP_MARKER:-${tmp}/k3d-owner}"
cleanup() {
  status=$?
  if [ -e "${K3D_OWNERSHIP_MARKER}" ]; then
    bash scripts/local/delete-k3d-cluster.sh >/dev/null 2>&1 || status=1
  fi
  rm -rf "${tmp}"
  exit "${status}"
}
trap cleanup EXIT

bash scripts/local/create-k3d-cluster.sh
kubectl --context "k3d-${K3D_CLUSTER_NAME}" apply -f tests/fixtures/crds
kubectl --context "k3d-${K3D_CLUSTER_NAME}" wait --for=condition=Established \
  crd/externalsecrets.external-secrets.io \
  crd/secretstores.external-secrets.io \
  crd/platformdependencies.fleet.atomi.cloud --timeout=2m

helm upgrade --install carbon chart --namespace default \
  --kube-context "k3d-${K3D_CLUSTER_NAME}" \
  --values chart/values.example.yaml --values chart/values.lapras.yaml --wait --timeout=2m
helm upgrade --install carbon-primordial primordial-chart --namespace diene --create-namespace \
  --kube-context "k3d-${K3D_CLUSTER_NAME}" \
  --values primordial-chart/values.example.yaml --values primordial-chart/values.lapras.yaml --wait --timeout=2m

kubectl --context "k3d-${K3D_CLUSTER_NAME}" get namespace feature-carbon-123 -o name
kubectl --context "k3d-${K3D_CLUSTER_NAME}" --namespace feature-carbon-123 get externalsecret carbon-token -o name
kubectl --context "k3d-${K3D_CLUSTER_NAME}" --namespace feature-carbon-123 get secretstore carbon-store -o name
kubectl --context "k3d-${K3D_CLUSTER_NAME}" --namespace diene get platformdependency carbon-mew -o json |
  jq -e '.spec.landscape == "mew" and .spec.placement.preferredHost == "raichu"' >/dev/null

echo "✅ Carbon branch namespace, platform SecretStore, and platform-shared dependency applied on k3d"
