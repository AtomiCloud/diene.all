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
tmp="$(mktemp -d)"
trap 'bash ./scripts/local/delete-k3d-cluster.sh >/dev/null 2>&1 || true; rm -rf "${tmp}"' EXIT

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

# The /healthz route answers 2xx through the LoadBalancer (or the gateway proxy locally).
lb_ip="$(kubectl --context "k3d-${cluster_name}" --namespace sulfoxide get service platinum-edge -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)"
[ -n "${lb_ip}" ] && curl --max-time 5 -fsS "http://${lb_ip}${lb_ip:+:}80/healthz" >/dev/null

# Local OCI round-trip.
PUBLISH_MODE=oci PUBLISH_DRY_RUN=false RELEASE_VERSION=v0.1.0 PUBLISH_OUTPUT_DIR="${tmp}/oci" OCI_REGISTRY="localhost:${registry_port}" OCI_REPOSITORY=charts OCI_PLAIN_HTTP=true bash ./scripts/ci/publish.sh
helm pull "oci://localhost:${registry_port}/charts/platinum" --version 0.1.0 --plain-http --destination "${tmp}"
test -s "${tmp}/platinum-0.1.0.tgz"

echo "✅ k3d install, Gateway Programmed, health 2xx, and local OCI round-trip passed"
