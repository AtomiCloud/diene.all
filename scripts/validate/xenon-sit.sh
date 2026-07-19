#!/usr/bin/env bash
# Xenon integration / SIT tier (edge chart, Q-I32). RESERVED for orchestration
# authorization: xenon is OFF on k3d/lapras (k3s bundles metrics-server), so the
# install + `kubectl top` proof runs on a landscape where the chart is actually
# enabled (a cloud/on-prem SIT cluster), never as a local k3d stand-in.
set -euo pipefail

namespace="${SIT_NAMESPACE:-sample}"
context="${SIT_CONTEXT:-}"
release="${RELEASE:-xenon}"

[ -z "${context}" ] && echo "❌ SIT_CONTEXT (a kubeconfig context where xenon is enabled) is required" >&2 && exit 1

# The wrapper requires serviceTree.platform == release namespace; install under
# the namespace matching the configured platform (default 'sample').
helm upgrade --install "${release}" chart --namespace "${namespace}" --create-namespace \
  --values chart/values.example.yaml --kube-context "${context}" --wait --timeout 5m

# metrics-server pods must go ready before the metrics API answers.
kubectl --context "${context}" --namespace "${namespace}" rollout status deployment/xenon-metrics --timeout 5m

# The edge-chart evidence: the resource metrics API answers post-install.
nodes="$(kubectl --context "${context}" top nodes 2>/dev/null || true)"
pods="$(kubectl --context "${context}" --namespace "${namespace}" top pods 2>/dev/null || true)"
[ -n "${nodes}" ] || {
  echo "❌ kubectl top nodes returned no data" >&2
  exit 1
}
[ -n "${pods}" ] || {
  echo "❌ kubectl top pods returned no data" >&2
  exit 1
}

echo "${nodes}"
echo "${pods}"
echo "✅ Xenon SIT integration proof complete on context ${context}"
