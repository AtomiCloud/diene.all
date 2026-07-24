#!/usr/bin/env bash
# sulfur cert-manager engine — integration tier (k3d install + behavior).
#
# This is the SERIALIZED strict proof: it stands up a throwaway k3d cluster,
# installs sulfur, waits for the controller/cainjector/webhook Deployments to go
# Available, then round-trips a self-signed Issuer + Certificate to Ready=True.
# Reserved for the orchestrated quiet-host proof window; not run in the unit tier.
set -euo pipefail

# Isolated-by-path identity: derive a unique cluster/registry/port set from the
# worktree path. With isolation enabled the identity is derived UNCONDITIONALLY —
# any preset K3D_* identity override is rejected so the run cannot be pointed at
# (and then destroy) a cluster/registry it does not own.
if [ "${K3D_ISOLATE_BY_PATH:-false}" = "true" ]; then
  [ -n "${K3D_CLUSTER_NAME:-}" ] && echo "❌ K3D_CLUSTER_NAME must not be preset when K3D_ISOLATE_BY_PATH=true (the isolated identity derives from the worktree path)" >&2 && exit 1
  [ -n "${K3D_REGISTRY_NAME:-}" ] && echo "❌ K3D_REGISTRY_NAME must not be preset when K3D_ISOLATE_BY_PATH=true (the isolated identity derives from the worktree path)" >&2 && exit 1
  [ -n "${K3D_REGISTRY_PORT:-}" ] && echo "❌ K3D_REGISTRY_PORT must not be preset when K3D_ISOLATE_BY_PATH=true (the isolated identity derives from the worktree path)" >&2 && exit 1
  [ -n "${K3D_HTTP_PORT:-}" ] && echo "❌ K3D_HTTP_PORT must not be preset when K3D_ISOLATE_BY_PATH=true (the isolated identity derives from the worktree path)" >&2 && exit 1
  isolation_key="$(printf '%s' "${PWD}" | sha256sum | cut -c1-8)"
  export K3D_CLUSTER_NAME="diene-sulfur-${isolation_key}"
  export K3D_REGISTRY_NAME="diene-sulfur-registry-${isolation_key}"
  export K3D_REGISTRY_PORT="$((20000 + (16#${isolation_key:0:4} % 10000)))"
  export K3D_HTTP_PORT="$((30000 + (16#${isolation_key:4:4} % 10000)))"
fi

cluster_name="${K3D_CLUSTER_NAME:-diene-sulfur}"
registry_port="${K3D_REGISTRY_PORT:-5001}"
tmp="$(mktemp -d)"
# Ownership-scoped cleanup: create claims exactly what it builds in this marker and
# refuses to adopt a pre-existing cluster/registry; delete tears down ONLY those
# owned resources. A refused (colliding) run writes no marker, so the trap never
# destroys a cluster/registry this run did not create.
export K3D_REQUIRE_OWNERSHIP=true
export K3D_OWNERSHIP_MARKER="${tmp}/owned"
trap 'bash ./scripts/local/delete-k3d-cluster.sh >/dev/null 2>&1 || true; rm -rf "${tmp}"' EXIT

bash ./scripts/local/create-k3d-cluster.sh
# Gateway API support is a mandatory sulfur value. cert-manager v1.20 refuses to
# start with that support enabled when the Gateway API CRDs are absent, so install
# and establish the checksum-pinned fixture dependency before Helm starts the
# controller. sulfur remains pure passthrough: these CRDs belong only to the k3d
# integration fixture, not to the product chart.
bash ./scripts/local/install-gateway-api-crds.sh \
  "k3d-${cluster_name}" "${tmp}/gateway-api-v1.4.1-standard-install.yaml"
# Derive the LPSM identity layer from the single labelPrefix (+ serviceTree); this
# generated upstream.global.commonLabels layer is the supported/mandatory render
# path and the validate.yaml guard rejects an install without it.
./scripts/local/gen-identity-values.sh chart/values.example.yaml chart/values.lapras.yaml >"${tmp}/identity.yaml"
helm upgrade --install sulfur chart --namespace sample --create-namespace \
  --kube-context "k3d-${cluster_name}" \
  --values chart/values.example.yaml --values chart/values.lapras.yaml --values "${tmp}/identity.yaml" --wait --timeout 5m

for dep in sulfur-upstream sulfur-upstream-webhook sulfur-upstream-cainjector; do
  kubectl --context "k3d-${cluster_name}" --namespace sample \
    wait --for=condition=Available "deployment/${dep}" --timeout=3m
done

kubectl --context "k3d-${cluster_name}" --namespace sample get pods \
  -l app.kubernetes.io/instance=sulfur -o json |
  jq -e '[.items[] | select(.metadata.labels["batch.kubernetes.io/job-name"] == null)] | length > 0 and all(.[]; .status.phase == "Running")' >/dev/null

# Behavior proof: a self-signed Issuer + Certificate round-trips to Ready=True.
kubectl --context "k3d-${cluster_name}" --namespace sample apply -f - <<'YAML'
apiVersion: cert-manager.io/v1
kind: Issuer
metadata:
  name: sulfur-selfsigned
spec:
  selfSigned: {}
---
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: sulfur-proof
spec:
  secretName: sulfur-proof-tls
  dnsNames:
    - proof.sulfur.local
  issuerRef:
    name: sulfur-selfsigned
    kind: Issuer
YAML
kubectl --context "k3d-${cluster_name}" --namespace sample \
  wait --for=condition=Ready certificate/sulfur-proof --timeout=3m

PUBLISH_MODE=oci PUBLISH_DRY_RUN=false RELEASE_VERSION=v0.1.0 PUBLISH_OUTPUT_DIR="${tmp}/oci" \
  OCI_REGISTRY="localhost:${registry_port}" OCI_REPOSITORY=charts OCI_PLAIN_HTTP=true \
  bash ./scripts/ci/publish.sh
helm pull "oci://localhost:${registry_port}/charts/diene-sulfur" --version 0.1.0 --plain-http --destination "${tmp}"
test -s "${tmp}/diene-sulfur-0.1.0.tgz"

echo "✅ k3d install, cert-manager health, self-signed Certificate Ready=True, and local OCI round-trip passed"
