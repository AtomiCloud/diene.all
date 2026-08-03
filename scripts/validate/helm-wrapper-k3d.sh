#!/usr/bin/env bash
set -euo pipefail

if [ "${K3D_ISOLATE_BY_PATH:-false}" = "true" ]; then
  isolation_key="$(printf '%s' "${PWD}" | sha256sum | cut -c1-8)"
  export K3D_CLUSTER_NAME="${K3D_CLUSTER_NAME:-diene-helm-wrapper-${isolation_key}}"
  export K3D_REGISTRY_NAME="${K3D_REGISTRY_NAME:-diene-wrapper-registry-${isolation_key}}"
  export K3D_REGISTRY_PORT="${K3D_REGISTRY_PORT:-$((20000 + (16#${isolation_key:0:4} % 10000)))}"
  export K3D_HTTP_PORT="${K3D_HTTP_PORT:-$((30000 + (16#${isolation_key:4:4} % 10000)))}"
fi

cluster_name="${K3D_CLUSTER_NAME:-diene-helm-wrapper}"
registry_port="${K3D_REGISTRY_PORT:-5001}"
tmp="$(mktemp -d)"
trap 'bash ./scripts/local/delete-k3d-cluster.sh >/dev/null 2>&1 || true; rm -rf "${tmp}"' EXIT

bash ./scripts/local/create-k3d-cluster.sh
bash ./scripts/local/vendor-chart-config.sh
helm dependency build chart
helm upgrade --install helm-wrapper chart --namespace sample --create-namespace --values chart/values.example.yaml --values chart/values.lapras.yaml --wait --timeout 5m
kubectl --context "k3d-${cluster_name}" --namespace sample wait --for=condition=Available deployment/wrapper-api --timeout=3m
# The Deployment's own selector, verbatim, so pod health is asserted over exactly
# the pods that Service selects. The pre-sync hook pod no longer carries the
# primary workload identity — it is born `app.kubernetes.io/name=wrapper-migration`
# with `component=migration` — so the `batch.kubernetes.io/job-name` filter this
# line used to need is obsolete: a migration pod cannot enter this selection at
# all, and `scripts/validate/helm-wrapper.sh labels` proves that with a sabotage
# control rather than leaving it to a downstream workaround.
kubectl --context "k3d-${cluster_name}" --namespace sample get pods -l app.kubernetes.io/name=wrapper-api,app.kubernetes.io/instance=helm-wrapper -o json | jq -e '.items | length > 0 and all(.[]; .status.phase == "Running")' >/dev/null

PUBLISH_MODE=oci PUBLISH_DRY_RUN=false RELEASE_VERSION=v0.1.0 PUBLISH_OUTPUT_DIR="${tmp}/oci" OCI_REGISTRY="localhost:${registry_port}" OCI_REPOSITORY=charts OCI_PLAIN_HTTP=true bash ./scripts/ci/publish.sh
helm pull "oci://localhost:${registry_port}/charts/diene-helm-wrapper" --version 0.1.0 --plain-http --destination "${tmp}"
test -s "${tmp}/diene-helm-wrapper-0.1.0.tgz"

echo "✅ k3d lapras install, pod health, and local OCI round-trip passed"
