#!/usr/bin/env bash
# Serialized integration tier: install only the consumed cert-manager CRDs, then apply Zinc.
set -euo pipefail

if [ "${K3D_ISOLATE_BY_PATH:-false}" = "true" ]; then
  [ -n "${K3D_CLUSTER_NAME:-}" ] && echo "❌ K3D_CLUSTER_NAME must not be preset when K3D_ISOLATE_BY_PATH=true" >&2 && exit 1
  [ -n "${K3D_REGISTRY_NAME:-}" ] && echo "❌ K3D_REGISTRY_NAME must not be preset when K3D_ISOLATE_BY_PATH=true" >&2 && exit 1
  [ -n "${K3D_REGISTRY_PORT:-}" ] && echo "❌ K3D_REGISTRY_PORT must not be preset when K3D_ISOLATE_BY_PATH=true" >&2 && exit 1
  [ -n "${K3D_HTTP_PORT:-}" ] && echo "❌ K3D_HTTP_PORT must not be preset when K3D_ISOLATE_BY_PATH=true" >&2 && exit 1
  isolation_key="$(printf '%s' "${PWD}" | sha256sum | cut -c1-8)"
  export K3D_CLUSTER_NAME="diene-zinc-${isolation_key}"
  export K3D_REGISTRY_NAME="diene-zinc-registry-${isolation_key}"
  export K3D_REGISTRY_PORT="$((20000 + (16#${isolation_key:0:4} % 10000)))"
  export K3D_HTTP_PORT="$((30000 + (16#${isolation_key:4:4} % 10000)))"
fi

cluster_name="${K3D_CLUSTER_NAME:-diene-zinc}"
registry_port="${K3D_REGISTRY_PORT:-5001}"
tmp="$(mktemp -d)"
artifact_dir="${ZINC_EVIDENCE_DIR:-${tmp}/evidence}"
mkdir -p "${artifact_dir}"
export K3D_REQUIRE_OWNERSHIP=true
export K3D_OWNERSHIP_MARKER="${tmp}/owned"
trap 'bash ./scripts/local/delete-k3d-cluster.sh >"${artifact_dir}/cleanup.log" 2>&1 || true; rm -rf "${tmp}"' EXIT

bash ./scripts/local/create-k3d-cluster.sh | tee "${artifact_dir}/cluster-create.log"

cert_manager_crds="${tmp}/cert-manager.crds.yaml"
curl -fsSL https://github.com/cert-manager/cert-manager/releases/download/v1.20.3/cert-manager.crds.yaml -o "${cert_manager_crds}"
printf '%s  %s\n' '8c2aea21520854c8c05f4b39909d0be6e2c1ea71544d5c4e2c4ba4f75a223ccc' "${cert_manager_crds}" | sha256sum --check
kubectl --context "k3d-${cluster_name}" apply --server-side --force-conflicts -f "${cert_manager_crds}" | tee "${artifact_dir}/cert-manager-crds.log"
kubectl --context "k3d-${cluster_name}" wait --for=condition=Established crd/clusterissuers.cert-manager.io crd/certificates.cert-manager.io --timeout=3m

cat >"${tmp}/externalsecret-crd.yaml" <<'YAML'
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  name: externalsecrets.external-secrets.io
spec:
  group: external-secrets.io
  names:
    kind: ExternalSecret
    plural: externalsecrets
    singular: externalsecret
  scope: Namespaced
  versions:
    - name: v1
      served: true
      storage: true
      schema:
        openAPIV3Schema:
          type: object
          x-kubernetes-preserve-unknown-fields: true
YAML
kubectl --context "k3d-${cluster_name}" apply --server-side -f "${tmp}/externalsecret-crd.yaml" | tee "${artifact_dir}/external-secret-crd.log"
kubectl --context "k3d-${cluster_name}" wait --for=condition=Established crd/externalsecrets.external-secrets.io --timeout=1m

helm upgrade --install zinc chart --namespace sample --create-namespace --kube-context "k3d-${cluster_name}" --values chart/values.pichu.yaml --values chart/values.local.yaml --wait --timeout 3m | tee "${artifact_dir}/registered-install.log"
kubectl --context "k3d-${cluster_name}" get clusterissuer/zinc-acme -o yaml >"${artifact_dir}/registered-issuer.yaml"
kubectl --context "k3d-${cluster_name}" --namespace sample get externalsecret/zinc-cloudflare -o yaml >"${artifact_dir}/external-secret.yaml"

helm upgrade zinc chart --namespace sample --kube-context "k3d-${cluster_name}" --values chart/values.entei.yaml --values chart/values.local.yaml --wait --timeout 3m | tee "${artifact_dir}/entei-upgrade.log"
kubectl --context "k3d-${cluster_name}" get clusterissuer/zinc-staging -o yaml >"${artifact_dir}/entei-staging.yaml"
kubectl --context "k3d-${cluster_name}" get clusterissuer/zinc-production -o yaml >"${artifact_dir}/entei-production.yaml"

helm template zinc chart --namespace sample --values chart/values.entei.yaml --values chart/values.local.yaml >"${artifact_dir}/entei-rendered.yaml"
bash ./scripts/validate/zinc-assert.sh no-certificates "${artifact_dir}/entei-rendered.yaml" >/dev/null
kubectl --context "k3d-${cluster_name}" --namespace sample apply -f - <<'YAML'
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: materializer-staging
  labels:
    atomi.cloud/owner: exposure-materializer
spec:
  secretName: materializer-stagingtls
  dnsNames:
    - api.zinc.nitroso.ci.eevee.dev.atomi.cloud
  issuerRef:
    kind: ClusterIssuer
    name: zinc-staging
---
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: materializer-production
  labels:
    atomi.cloud/owner: exposure-materializer
spec:
  secretName: materializer-productiontls
  dnsNames:
    - api.zinc.nitroso.review.eevee.dev.atomi.cloud
  issuerRef:
    kind: ClusterIssuer
    name: zinc-production
YAML
kubectl --context "k3d-${cluster_name}" --namespace sample get certificates -o json >"${artifact_dir}/materializer-certificates.json"
jq -e '[.items[] | select(.metadata.labels["atomi.cloud/owner"] == "exposure-materializer") | .spec.issuerRef.name] | sort == ["zinc-production", "zinc-staging"]' "${artifact_dir}/materializer-certificates.json" >/dev/null

mkdir -p "${artifact_dir}/oci" "${artifact_dir}/oci-pull"
PUBLISH_MODE=oci PUBLISH_DRY_RUN=false RELEASE_VERSION=v0.1.0 PUBLISH_OUTPUT_DIR="${artifact_dir}/oci" OCI_REGISTRY="localhost:${registry_port}" OCI_REPOSITORY=charts OCI_PLAIN_HTTP=true bash ./scripts/ci/publish.sh | tee "${artifact_dir}/oci-push.log"
helm pull "oci://localhost:${registry_port}/charts/diene-zinc" --version 0.1.0 --plain-http --destination "${artifact_dir}/oci-pull"
test -s "${artifact_dir}/oci-pull/diene-zinc-0.1.0.tgz"

printf 'status=passed\nregisteredIssuer=zinc-acme\nstagingIssuer=zinc-staging\nproductionIssuer=zinc-production\n' >"${artifact_dir}/proof.env"
echo "✅ zinc CRD apply, registered/ENTEI issuer refs, materializer-owned Certificate refs, and OCI round-trip passed"
