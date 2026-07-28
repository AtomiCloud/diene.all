#!/usr/bin/env bash
set -euo pipefail

[ "${K3D_ISOLATE_BY_PATH:-}" = true ] || {
  echo "❌ K3D_ISOLATE_BY_PATH=true is mandatory for the Lithium proof" >&2
  exit 1
}
isolation_key="$(printf %s "${PWD}" | sha256sum | cut -c1-8)"
export K3D_CLUSTER_NAME="${K3D_CLUSTER_NAME:-diene-lithium-${isolation_key}}"
export K3D_REGISTRY_NAME="${K3D_REGISTRY_NAME:-diene-lithium-registry-${isolation_key}}"
export K3D_REGISTRY_PORT="${K3D_REGISTRY_PORT:-$((20000 + (16#${isolation_key:0:4} % 10000)))}"
export K3D_HTTP_PORT="${K3D_HTTP_PORT:-$((30000 + (16#${isolation_key:4:4} % 10000)))}"
export K3D_OWNER_ID="${K3D_OWNER_ID:-lithium-${isolation_key}-$$}"
tmp="$(mktemp -d)"
export K3D_OWNERSHIP_MARKER="${tmp}/owner"
trap 'test ! -e "${K3D_OWNERSHIP_MARKER}" || bash scripts/local/delete-k3d-cluster.sh; rm -rf "${tmp}"' EXIT
bash scripts/local/create-k3d-cluster.sh
kubectl --context "k3d-${K3D_CLUSTER_NAME}" create namespace lithium-lapras-001
kubectl --context "k3d-${K3D_CLUSTER_NAME}" -n lithium-lapras-001 create secret generic lithium-lapras-db --from-literal=DB_URL=postgres://local
kubectl --context "k3d-${K3D_CLUSTER_NAME}" -n lithium-lapras-001 create secret generic lithium-lapras-boot --from-literal=SEED_M2M_CLIENT_ID=seed --from-literal=SEED_M2M_CLIENT_SECRET=seed
for gate_case in missing blank; do
  # shellcheck disable=SC2016 # The pod, not this shell, expands credential variables.
  args=(run "lithium-gate-${gate_case}" --image=busybox:1.36.1 --restart=Never --overrides='{"spec":{"securityContext":{"runAsNonRoot":true,"runAsUser":10001,"runAsGroup":10001}}}' --command -- sh -ec 'test -n "$DB_URL" && test -n "$SEED_M2M_CLIENT_ID" && test -n "$SEED_M2M_CLIENT_SECRET"')
  if [ "${gate_case}" = blank ]; then
    args+=(--env=DB_URL= --env=SEED_M2M_CLIENT_ID= --env=SEED_M2M_CLIENT_SECRET=)
  fi
  kubectl --context "k3d-${K3D_CLUSTER_NAME}" -n lithium-lapras-001 "${args[@]}"
  kubectl --context "k3d-${K3D_CLUSTER_NAME}" -n lithium-lapras-001 wait --for=jsonpath='{.status.containerStatuses[0].state.terminated.exitCode}'=1 "pod/lithium-gate-${gate_case}" --timeout=2m
done
helm upgrade --install lithium chart --namespace lithium-lapras-001 --kube-context "k3d-${K3D_CLUSTER_NAME}" --values chart/values.lapras.yaml
kubectl --context "k3d-${K3D_CLUSTER_NAME}" -n lithium-lapras-001 get service lithium-management
echo "✅ Lithium Garden-local chart installed on k3d (fork image readiness is external-fork CI)"
