#!/usr/bin/env bash
# Chlorine integration tier: install the reloader engine on an ephemeral k3d
# cluster, prove the controller is healthy, and prove the SoS last hop — an
# annotated Deployment whose referenced Secret changes is rolling-restarted by
# Reloader (annotation opt-in; autoReloadAll stays off).
set -euo pipefail

if [ "${K3D_ISOLATE_BY_PATH:-false}" = "true" ]; then
  isolation_key="$(printf '%s' "${PWD}" | sha256sum | cut -c1-8)"
  export K3D_CLUSTER_NAME="${K3D_CLUSTER_NAME:-diene-chlorine-${isolation_key}}"
  export K3D_REGISTRY_NAME="${K3D_REGISTRY_NAME:-diene-chlorine-registry-${isolation_key}}"
  export K3D_REGISTRY_PORT="${K3D_REGISTRY_PORT:-$((20000 + (16#${isolation_key:0:4} % 10000)))}"
  export K3D_HTTP_PORT="${K3D_HTTP_PORT:-$((30000 + (16#${isolation_key:4:4} % 10000)))}"
fi

cluster_name="${K3D_CLUSTER_NAME:-diene-chlorine}"
release="${RELEASE:-chlorine}"
namespace="${NAMESPACE:-reloader}"
sit_namespace="${SIT_NAMESPACE:-chlorine-sit}"
context="k3d-${cluster_name}"
tmp="$(mktemp -d)"
trap 'bash ./scripts/local/delete-k3d-cluster.sh >/dev/null 2>&1 || true; rm -rf "${tmp}"' EXIT

bash ./scripts/local/create-k3d-cluster.sh
bash ./scripts/local/vendor-reloader.sh build

helm upgrade --install "${release}" chart --namespace "${namespace}" --create-namespace \
  --values chart/values.example.yaml --values chart/values.lapras.yaml --wait --timeout 6m

# The reloader controller must be Available.
kubectl --context "${context}" --namespace "${namespace}" wait \
  --for=condition=Available deployment/chlorine-reloader --timeout=4m

# An annotated Deployment referencing a Secret is the SoS last-hop target.
kubectl --context "${context}" create namespace "${sit_namespace}" --dry-run=client -o yaml | kubectl --context "${context}" apply -f -
kubectl --context "${context}" --namespace "${sit_namespace}" create secret generic demo-secret \
  --from-literal=token=before --dry-run=client -o yaml | kubectl --context "${context}" apply -f -
cat >"${tmp}/demo.yaml" <<YAML
apiVersion: apps/v1
kind: Deployment
metadata:
  name: demo
  namespace: ${sit_namespace}
  annotations:
    reloader.stakater.com/auto: "true"
spec:
  replicas: 1
  selector:
    matchLabels:
      app: demo
  template:
    metadata:
      labels:
        app: demo
    spec:
      containers:
        - name: demo
          image: registry.k8s.io/pause:3.9
          envFrom:
            - secretRef:
                name: demo-secret
YAML
kubectl --context "${context}" apply -f "${tmp}/demo.yaml"
kubectl --context "${context}" --namespace "${sit_namespace}" rollout status deployment/demo --timeout=2m

before_generation="$(kubectl --context "${context}" --namespace "${sit_namespace}" get deployment demo -o jsonpath='{.metadata.generation}')"

# Rotate the referenced Secret — Reloader must roll the annotated Deployment.
kubectl --context "${context}" --namespace "${sit_namespace}" create secret generic demo-secret \
  --from-literal=token=after --dry-run=client -o yaml | kubectl --context "${context}" apply -f -

reloaded=false
for _ in $(seq 1 60); do
  reloaded_from="$(kubectl --context "${context}" --namespace "${sit_namespace}" get deployment demo \
    -o jsonpath='{.spec.template.metadata.annotations.reloader\.stakater\.com/last-reloaded-from}' 2>/dev/null || true)"
  after_generation="$(kubectl --context "${context}" --namespace "${sit_namespace}" get deployment demo -o jsonpath='{.metadata.generation}')"
  if [ -n "${reloaded_from}" ] || [ "${after_generation}" -gt "${before_generation}" ]; then
    reloaded=true
    break
  fi
  sleep 3
done

[ "${reloaded}" != "true" ] && echo "❌ Reloader did not restart the annotated Deployment after its Secret changed" >&2 && exit 1
kubectl --context "${context}" --namespace "${sit_namespace}" rollout status deployment/demo --timeout=2m

# Negative control: an un-annotated Deployment referencing an un-annotated Secret
# is NOT touched (annotation opt-in, not auto-reload-all).
kubectl --context "${context}" --namespace "${sit_namespace}" create secret generic quiet-secret \
  --from-literal=token=before --dry-run=client -o yaml | kubectl --context "${context}" apply -f -
sed 's/name: demo/name: quiet/; s/app: demo/app: quiet/; s/name: demo-secret/name: quiet-secret/; /reloader.stakater.com\/auto/d' "${tmp}/demo.yaml" >"${tmp}/quiet.yaml"
kubectl --context "${context}" apply -f "${tmp}/quiet.yaml"
kubectl --context "${context}" --namespace "${sit_namespace}" rollout status deployment/quiet --timeout=2m
quiet_before="$(kubectl --context "${context}" --namespace "${sit_namespace}" get deployment quiet -o jsonpath='{.metadata.generation}')"
kubectl --context "${context}" --namespace "${sit_namespace}" create secret generic quiet-secret \
  --from-literal=token=after --dry-run=client -o yaml | kubectl --context "${context}" apply -f -
sleep 20
quiet_after="$(kubectl --context "${context}" --namespace "${sit_namespace}" get deployment quiet -o jsonpath='{.metadata.generation}')"
[ "${quiet_after}" != "${quiet_before}" ] && echo "❌ Reloader restarted an un-annotated Deployment (opt-in violated)" >&2 && exit 1

echo "✅ k3d reloader engine healthy; annotated Secret change rolled the workload, un-annotated stayed put"
