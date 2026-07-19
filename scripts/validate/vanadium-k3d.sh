#!/usr/bin/env bash
# ### vanadium-k3d
# #### source: vanadium
# Integration-tier proof (reserved for the orchestrated live window). Installs the
# policy set on a throwaway k3d cluster and proves the local warn/enforce behavior
# and apiserver VAP metrics. Not run by the static CI tier.
set -euo pipefail

if [ "${K3D_ISOLATE_BY_PATH:-false}" = "true" ]; then
  isolation_key="$(printf '%s' "${PWD}" | sha256sum | cut -c1-8)"
  export K3D_CLUSTER_NAME="${K3D_CLUSTER_NAME:-diene-vanadium-${isolation_key}}"
  export K3D_REGISTRY_PORT="${K3D_REGISTRY_PORT:-$((20000 + (16#${isolation_key:0:4} % 10000)))}"
  export K3D_HTTP_PORT="${K3D_HTTP_PORT:-$((30000 + (16#${isolation_key:4:4} % 10000)))}"
fi

cluster_name="${K3D_CLUSTER_NAME:-diene-vanadium}"
release="${RELEASE:-vanadium}"
namespace="${NAMESPACE:-fleet}"
deny_overlay="${tmp:-/tmp}/vanadium-deny.yaml"
trap 'bash ./scripts/local/delete-k3d-cluster.sh >/dev/null 2>&1 || true' EXIT

bash ./scripts/local/create-k3d-cluster.sh
context="k3d-${cluster_name}"

# Policies apply cluster-wide; install into the fleet namespace for ownership only.
helm upgrade --install "${release}" chart --namespace "${namespace}" --create-namespace \
  --values chart/values.example.yaml --values chart/values.lapras.yaml --wait --timeout 5m
kubectl --context "${context}" get validatingadmissionpolicies -o name | grep "vanadium-"

# Warn posture: a violating manifest is admitted and returns an admission Warning.
warn_log="$(mktemp)"
if kubectl --context "${context}" apply -f chart/tests/cases/disallowlatest/bad.yaml 2>"${warn_log}"; then
  grep -qi 'Warning:' "${warn_log}"
else
  echo "❌ warn-mode violating manifest was denied (expected admitted with warning)" >&2
  exit 1
fi
kubectl --context "${context}" delete -f chart/tests/cases/disallowlatest/bad.yaml --ignore-not-found >/dev/null

# Enforce posture: flip the rule to Deny; the same manifest is now rejected.
yq -o=json ea -o=yaml '.' chart/values.example.yaml |
  yq -o=yaml '.policies.disallowLatest.actions = ["Deny"]' >"${deny_overlay}"
helm upgrade --install "${release}" chart --namespace "${namespace}" \
  --values chart/values.lapras.yaml --values "${deny_overlay}" --wait --timeout 5m >/dev/null
if kubectl --context "${context}" apply -f chart/tests/cases/disallowlatest/bad.yaml 2>/dev/null; then
  echo "❌ deny-mode violating manifest was admitted (expected denied)" >&2
  exit 1
fi

# Local compliance-view half: apiserver VAP admission metrics were recorded.
kubectl --context "${context}" get --raw /metrics | grep -q 'vap_admission'

echo "✅ vanadium k3d install, warn/enforce behavior, and VAP metrics passed"
