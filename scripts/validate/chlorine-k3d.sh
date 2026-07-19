#!/usr/bin/env bash
# ### chlorine-integration
# #### source: chlorine
#
# Integration tier of the testing pyramid (S30/Q-I27): the SoS last hop — an
# annotation-opt-in Deployment restarts when its Secret changes. Requires a
# running k3d lapras cluster (scripts/local/create-k3d-cluster.sh). This is the
# serialized live proof; it is NOT run in the local/static turn.
#
# Sandbox isolation (RB-66): the cluster, registry, ports, and kube context are
# all derived from a path-keyed isolation key (scripts/local/k3d-isolation.sh),
# and EVERY helm/kubectl call is pinned to the explicit k3d-<cluster> context —
# no command relies on k3d's mutation of the ambient current-context, so a
# reused or foreign context is never touched. The fixed-name test
# Secret/Deployment are created, observed, and removed transactionally in that
# same pinned context and namespace (success or failure) so a reused cluster
# never retains them; the cluster itself is torn down by the required
# delete-k3d-cluster.sh step in the proof handoff.
set -euo pipefail

_here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${_here}/../local/k3d-isolation.sh"

release="${RELEASE:-chlorine}"
namespace="${NAMESPACE:-sample}"
context="${K3D_CONTEXT}"
tmp="$(mktemp -d)"
# Transactional cleanup: delete the fixed Secret+Deployment together in the
# pinned context+namespace, then the temp dir. --ignore-not-found keeps it
# idempotent; || true so a missing cluster or namespace never masks the result.
trap 'kubectl --context "${context}" delete --ignore-not-found -n "${namespace}" secret reload-trigger deployment reload-target >/dev/null 2>&1 || true; rm -rf "${tmp}"' EXIT

# 1. Install the chlorine Reloader chart in the service namespace (platform == namespace).
helm dependency build chart
helm upgrade --install "${release}" chart --kube-context "${context}" --namespace "${namespace}" --create-namespace \
  --values chart/values.example.yaml --values chart/values.lapras.yaml --wait --timeout 5m
kubectl --context "${context}" -n "${namespace}" rollout status deployment/"${release}-reloader" --timeout=2m

# 2. Create an annotation-opt-in Deployment that references a Secret. The
# manifest carries no hard-coded namespace; it is applied into ${namespace} so
# the fixture, waits, patch, and cleanup all target one consistent namespace.
cat >"${tmp}/workload.yaml" <<'EOF'
apiVersion: v1
kind: Secret
metadata:
  name: reload-trigger
stringData:
  value: v1
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: reload-target
  annotations:
    reloader.stakater.com/auto: 'true'
spec:
  replicas: 1
  selector:
    matchLabels:
      app: reload-target
  template:
    metadata:
      labels:
        app: reload-target
    spec:
      containers:
        - name: app
          image: ghcr.io/stefanprodan/podinfo:6.9.2
          env:
            - name: SECRET_VALUE
              valueFrom:
                secretKeyRef:
                  name: reload-trigger
                  key: value
EOF
kubectl --context "${context}" -n "${namespace}" apply -f "${tmp}/workload.yaml"
kubectl --context "${context}" -n "${namespace}" rollout status deployment/reload-target --timeout=2m
pod_before="$(kubectl --context "${context}" -n "${namespace}" get pods -l app=reload-target -o jsonpath='{.items[0].metadata.name}')"
[ -z "${pod_before}" ] && echo "❌ reload-target pod not found before mutation" >&2 && exit 1

# 3. Mutate the Secret and wait for Reloader to roll out a new pod.
kubectl --context "${context}" -n "${namespace}" patch secret reload-trigger --type merge -p '{"stringData":{"value":"v2"}}'

deadline=$((SECONDS + 150))
pod_after="${pod_before}"
while [ "${SECONDS}" -lt "${deadline}" ]; do
  pod_after="$(kubectl --context "${context}" -n "${namespace}" get pods -l app=reload-target -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
  if [ -n "${pod_after}" ] && [ "${pod_after}" != "${pod_before}" ]; then
    break
  fi
  sleep 3
done

if [ -z "${pod_after}" ] || [ "${pod_after}" = "${pod_before}" ]; then
  echo "❌ reload-target was not restarted after the Secret change (SoS last hop failed)" >&2
  exit 1
fi
kubectl --context "${context}" -n "${namespace}" rollout status deployment/reload-target --timeout=2m

echo "✅ Chlorine integration: annotated Deployment restarted on Secret change (${pod_before} → ${pod_after})"
