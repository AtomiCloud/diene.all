#!/usr/bin/env bash
# Zinc integration tier: install the issuer chart on an ephemeral k3d cluster with
# the cert-manager and external-secrets CRDs present, and prove the reusable
# DNS-01 ClusterIssuer(s) apply. Live ACME issuance needs real Let's Encrypt +
# Cloudflare credentials and is a Layer C pre-release step; here we assert the
# objects APPLY with the intended ACME directories and solver restriction, that
# zinc renders no Certificate, and that a materializer-owned Certificate may
# reference either rail.
set -euo pipefail

if [ "${K3D_ISOLATE_BY_PATH:-false}" = "true" ]; then
  isolation_key="$(printf '%s' "${PWD}" | sha256sum | cut -c1-8)"
  export K3D_CLUSTER_NAME="${K3D_CLUSTER_NAME:-diene-zinc-${isolation_key}}"
  export K3D_REGISTRY_NAME="${K3D_REGISTRY_NAME:-diene-zinc-registry-${isolation_key}}"
  export K3D_REGISTRY_PORT="${K3D_REGISTRY_PORT:-$((20000 + (16#${isolation_key:0:4} % 10000)))}"
  export K3D_HTTP_PORT="${K3D_HTTP_PORT:-$((30000 + (16#${isolation_key:4:4} % 10000)))}"
fi

cluster_name="${K3D_CLUSTER_NAME:-diene-zinc}"
release="${RELEASE:-zinc}"
namespace="${NAMESPACE:-cert-manager}"
context="k3d-${cluster_name}"
cert_manager_version="${CERT_MANAGER_VERSION:-v1.20.3}"
external_secrets_version="${EXTERNAL_SECRETS_VERSION:-v0.10.4}"
prod_url="https://acme-v02.api.letsencrypt.org/directory"
staging_url="https://acme-staging-v02.api.letsencrypt.org/directory"
tmp="$(mktemp -d)"
trap 'bash ./scripts/local/delete-k3d-cluster.sh >/dev/null 2>&1 || true; rm -rf "${tmp}"' EXIT

bash ./scripts/local/create-k3d-cluster.sh

# The CRDs zinc's own resources bind to (owned by other nodes in production):
# cert-manager supplies the ClusterIssuer/Certificate kinds; external-secrets
# supplies the ExternalSecret kind.
kubectl --context "${context}" apply -f \
  "https://github.com/cert-manager/cert-manager/releases/download/${cert_manager_version}/cert-manager.crds.yaml"
kubectl --context "${context}" apply -f \
  "https://raw.githubusercontent.com/external-secrets/external-secrets/${external_secrets_version}/deploy/crds/bundle.yaml"
kubectl --context "${context}" wait --for=condition=Established \
  crd/clusterissuers.cert-manager.io crd/certificates.cert-manager.io crd/externalsecrets.external-secrets.io --timeout=2m

# Registered-fleet install (lapras landscape, LE staging directory).
helm upgrade --install "${release}" chart --namespace "${namespace}" --create-namespace \
  --values chart/values.lapras.yaml --wait --timeout 3m

kubectl --context "${context}" get clusterissuer zinc-letsencrypt -o json |
  jq -e --arg staging "${staging_url}" '.spec.acme.server == $staging' >/dev/null
kubectl --context "${context}" --namespace "${namespace}" get externalsecret zinc-secrets >/dev/null
echo "✅ registered-fleet ClusterIssuer applied with the LE staging directory"

# ENTEI host-role install: the staging+production pair with the hosted-zone
# solver restriction, from the one reusable definition.
helm upgrade --install "${release}" chart --namespace "${namespace}" \
  --values chart/values.entei.yaml --wait --timeout 3m

kubectl --context "${context}" get clusterissuer zinc-letsencrypt-staging -o json |
  jq -e --arg staging "${staging_url}" '
    .spec.acme.server == $staging
    and (.spec.acme.solvers[0].selector.dnsZones | index("dev.atomi.cloud")) != null
  ' >/dev/null
kubectl --context "${context}" get clusterissuer zinc-letsencrypt-production -o json |
  jq -e --arg prod "${prod_url}" '
    .spec.acme.server == $prod
    and (.spec.acme.solvers[0].selector.dnsZones | index("dev.atomi.cloud")) != null
  ' >/dev/null
echo "✅ ENTEI staging+production ClusterIssuers applied with the hosted-zone restriction"

# Zinc itself renders and owns no Certificate.
cert_in_cluster="$(kubectl --context "${context}" get certificate -A --no-headers 2>/dev/null | wc -l)"
[ "${cert_in_cluster}" -ne 0 ] && echo "❌ zinc install created a Certificate" >&2 && exit 1

# A materializer-owned exact-name Certificate may reference either rail (validated
# server-side against the CRD) — proving the rail is referenceable while zinc owns
# no Certificate of its own.
cat >"${tmp}/materializer-cert.yaml" <<YAML
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: eevee-exact-example
  namespace: ${namespace}
spec:
  secretName: eevee-exact-example-tls
  commonName: api.svc.platform.eevee.entei.dev.atomi.cloud
  dnsNames:
    - api.svc.platform.eevee.entei.dev.atomi.cloud
  issuerRef:
    name: zinc-letsencrypt-production
    kind: ClusterIssuer
    group: cert-manager.io
YAML
kubectl --context "${context}" apply --dry-run=server -f "${tmp}/materializer-cert.yaml" >/dev/null
echo "✅ a materializer-owned exact-name Certificate can reference the zinc rail (zinc owns none)"

echo "✅ k3d zinc issuer chart applied cleanly (ClusterIssuers Ready needs live LE/CF — Layer C)"
