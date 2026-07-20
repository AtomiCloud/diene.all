#!/usr/bin/env bash
# Install the exact Gateway API CRDs required before starting a Gateway-enabled
# cert-manager controller. cert-manager v1.20 exits when enableGatewayAPI=true
# but gateway.networking.k8s.io/v1 is absent during controller startup.
set -euo pipefail

context="${1:?usage: install-gateway-api-crds.sh <kube-context> <bundle-path>}"
bundle="${2:?usage: install-gateway-api-crds.sh <kube-context> <bundle-path>}"

case "${bundle}" in
/*) ;;
*)
  echo "❌ Gateway API bundle path must be absolute" >&2
  exit 1
  ;;
esac

gateway_api_url="https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.4.1/standard-install.yaml"
gateway_api_sha256="73b91b77f6be023a8c92c969fc664e5bd3b1a28aea59eac9ebc904607354dad2" # gitleaks:allow

curl -fsSL --output "${bundle}" "${gateway_api_url}"
printf '%s  %s\n' "${gateway_api_sha256}" "${bundle}" | sha256sum -c -

kubectl --context "${context}" apply --server-side -f "${bundle}"
kubectl --context "${context}" wait --for=condition=Established --timeout=2m \
  crd/gatewayclasses.gateway.networking.k8s.io \
  crd/gateways.gateway.networking.k8s.io \
  crd/httproutes.gateway.networking.k8s.io

# Match cert-manager's startup discovery precondition instead of assuming that
# an accepted CRD write is already visible through API discovery.
kubectl --context "${context}" api-resources \
  --api-group=gateway.networking.k8s.io -o name |
  rg -qx 'gateways.gateway.networking.k8s.io'

echo "✅ Gateway API v1.4.1 CRDs installed and discoverable"
