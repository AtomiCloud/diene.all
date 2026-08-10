#!/usr/bin/env bash
# Sulfur integration tier: install the cert-manager engine on an ephemeral k3d
# cluster, prove the controller + cainjector + webhook are healthy, and
# round-trip a self-signed Issuer + Certificate to Ready=True.
set -euo pipefail

if [ "${K3D_ISOLATE_BY_PATH:-false}" = "true" ]; then
  isolation_key="$(printf '%s' "${PWD}" | sha256sum | cut -c1-8)"
  export K3D_CLUSTER_NAME="${K3D_CLUSTER_NAME:-diene-sulfur-${isolation_key}}"
  export K3D_REGISTRY_NAME="${K3D_REGISTRY_NAME:-diene-sulfur-registry-${isolation_key}}"
  export K3D_REGISTRY_PORT="${K3D_REGISTRY_PORT:-$((20000 + (16#${isolation_key:0:4} % 10000)))}"
  export K3D_HTTP_PORT="${K3D_HTTP_PORT:-$((30000 + (16#${isolation_key:4:4} % 10000)))}"
fi

cluster_name="${K3D_CLUSTER_NAME:-diene-sulfur}"
release="${RELEASE:-sulfur}"
namespace="${NAMESPACE:-cert-manager}"
sit_namespace="${SIT_NAMESPACE:-sulfur-sit}"
context="k3d-${cluster_name}"
gateway_api_version="${GATEWAY_API_VERSION:-v1.2.1}"
tmp="$(mktemp -d)"
trap 'bash ./scripts/local/delete-k3d-cluster.sh >/dev/null 2>&1 || true; rm -rf "${tmp}"' EXIT

bash ./scripts/local/create-k3d-cluster.sh
bash ./scripts/local/vendor-cert-manager.sh build

# Gateway API CRDs so the enabled Gateway API integration has real APIs to watch.
kubectl --context "${context}" apply -f \
  "https://github.com/kubernetes-sigs/gateway-api/releases/download/${gateway_api_version}/standard-install.yaml"

helm upgrade --install "${release}" chart --namespace "${namespace}" --create-namespace \
  --values chart/values.example.yaml --values chart/values.lapras.yaml --wait --timeout 6m

# The three engine workloads must be Available.
for component in cert-manager cert-manager-cainjector cert-manager-webhook; do
  kubectl --context "${context}" --namespace "${namespace}" wait \
    --for=condition=Available "deployment/${component}" --timeout=4m
done

# Round-trip a self-signed Issuer + Certificate to Ready=True.
kubectl --context "${context}" create namespace "${sit_namespace}" --dry-run=client -o yaml | kubectl --context "${context}" apply -f -
cat >"${tmp}/selfsigned.yaml" <<YAML
apiVersion: cert-manager.io/v1
kind: Issuer
metadata:
  name: sulfur-selfsigned
  namespace: ${sit_namespace}
spec:
  selfSigned: {}
---
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: sulfur-selfsigned-cert
  namespace: ${sit_namespace}
spec:
  secretName: sulfur-selfsigned-tls
  isCA: false
  commonName: sulfur.local.example.invalid
  dnsNames:
    - sulfur.local.example.invalid
  privateKey:
    algorithm: ECDSA
    size: 256
  issuerRef:
    name: sulfur-selfsigned
    kind: Issuer
    group: cert-manager.io
YAML
kubectl --context "${context}" apply -f "${tmp}/selfsigned.yaml"
kubectl --context "${context}" --namespace "${sit_namespace}" wait \
  --for=condition=Ready certificate/sulfur-selfsigned-cert --timeout=3m
kubectl --context "${context}" --namespace "${sit_namespace}" get secret sulfur-selfsigned-tls -o json |
  jq -e '.data["tls.crt"] != null and .data["tls.key"] != null' >/dev/null

echo "✅ k3d cert-manager engine healthy; self-signed Certificate reached Ready=True"
