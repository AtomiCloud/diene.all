#!/usr/bin/env bash
# ### vanadium-k3d
# #### source: vanadium
# Integration-tier proof (reserved for the orchestrated live window). Installs the
# policy set on a throwaway k3d cluster and proves the local warn/enforce behavior
# and apiserver VAP metrics. Not run by the static CI tier.
set -euo pipefail

[ "${K3D_ISOLATE_BY_PATH:-false}" != "true" ] && echo "❌ set K3D_ISOLATE_BY_PATH=true" >&2 && exit 1

isolation_key="$(printf '%s' "${PWD}" | sha256sum | cut -c1-8)"
export K3D_CLUSTER_NAME="${K3D_CLUSTER_NAME:-diene-vanadium-${isolation_key}}"
export K3D_REGISTRY_NAME="${K3D_REGISTRY_NAME:-diene-vanadium-registry-${isolation_key}}"
export K3D_REGISTRY_PORT="${K3D_REGISTRY_PORT:-$((20000 + (16#${isolation_key:0:4} % 10000)))}"
export K3D_HTTP_PORT="${K3D_HTTP_PORT:-$((30000 + (16#${isolation_key:4:4} % 10000)))}"

cluster_name="${K3D_CLUSTER_NAME}"
release="${RELEASE:-vanadium}"
namespace="${NAMESPACE:-fleet}"
evidence_dir="${VANADIUM_EVIDENCE_DIR:?set VANADIUM_EVIDENCE_DIR to an absolute durable directory}"
case "${evidence_dir}" in /*) ;; *)
  echo "❌ VANADIUM_EVIDENCE_DIR must be absolute" >&2
  exit 1
  ;;
esac
mkdir -p "${evidence_dir}"
deny_overlay="${evidence_dir}/vanadium-deny-${isolation_key}.yaml"
warn_log="${evidence_dir}/vanadium-warn-${isolation_key}.log"
before_metrics="${evidence_dir}/apiserver-vap-before-${isolation_key}.prom"
after_metrics="${evidence_dir}/apiserver-vap-after-${isolation_key}.prom"
trap 'rm -f "${deny_overlay}"; bash ./scripts/local/delete-k3d-cluster.sh >/dev/null 2>&1 || true' EXIT

wait_for_vap_activation() {
  local posture="$1"
  local readiness_log="${evidence_dir}/vanadium-${posture}-readiness-${isolation_key}.log"
  local deadline=$((SECONDS + 60))
  local attempt=0

  while ((SECONDS < deadline)); do
    ((attempt += 1))
    if kubectl --context "${context}" apply --dry-run=server -f chart/tests/cases/disallowlatest/bad.yaml \
      >/dev/null 2>"${readiness_log}"; then
      if [[ ${posture} == "warn" ]] && rg -q '^Warning:' "${readiness_log}"; then
        echo "✅ VAP Warn posture became active after ${attempt} server-side dry-run attempt(s)" >&2
        return 0
      fi
    elif [[ ${posture} == "deny" ]] && rg -qi 'ValidatingAdmissionPolicy|denied the request' "${readiness_log}"; then
      echo "✅ VAP Deny posture became active after ${attempt} server-side dry-run attempt(s)" >&2
      return 0
    fi
    sleep 1
  done

  echo "❌ VAP ${posture} posture did not become active within 60s; last server-side dry-run stderr retained at ${readiness_log}" >&2
  if [[ -s ${readiness_log} ]]; then
    sed 's/^/  /' "${readiness_log}" >&2
  fi
  return 1
}

bash ./scripts/local/create-k3d-cluster.sh
context="k3d-${cluster_name}"

# Policies apply cluster-wide; install into the fleet namespace for ownership only.
helm upgrade --install "${release}" chart --namespace "${namespace}" --create-namespace \
  --kube-context "${context}" --values chart/values.example.yaml --values chart/values.lapras.yaml --wait --timeout 5m
kubectl --context "${context}" get validatingadmissionpolicies -o name | grep "vanadium-"
wait_for_vap_activation warn

# Capture exactly the target policy/binding Warn counter before the violating request.
kubectl --context "${context}" get --raw /metrics >"${before_metrics}"
before_count="$(awk '/^apiserver_validating_admission_policy_check_total[{]/ && /policy="vanadium-disallowlatest"/ && /policy_binding="vanadium-disallowlatest"/ && /enforcement_action="warn"/ { sum += $NF } END { print sum + 0 }' "${before_metrics}")"

# Warn posture: a violating manifest is admitted and returns an admission Warning.
if ! kubectl --context "${context}" apply -f chart/tests/cases/disallowlatest/bad.yaml 2>"${warn_log}"; then
  if rg -qi ' is invalid:|required value|invalid value|unknown field' "${warn_log}"; then
    echo "❌ warn-mode manifest failed Kubernetes structural validation (not a VAP Warning); stderr retained at ${warn_log}" >&2
  else
    echo "❌ warn-mode manifest apply failed before an admission Warning was observed; stderr retained at ${warn_log}" >&2
  fi
  exit 1
fi
if ! rg -qi '^Warning:' "${warn_log}"; then
  echo "❌ warn-mode violating manifest was admitted without the expected Warning; stderr retained at ${warn_log}" >&2
  exit 1
fi
kubectl --context "${context}" delete -f chart/tests/cases/disallowlatest/bad.yaml --ignore-not-found >/dev/null

# Enforce posture: flip the rule to Deny; the same manifest is now rejected.
yq -o=json ea -o=yaml '.' chart/values.example.yaml |
  yq -o=yaml '.policies.disallowLatest.actions = ["Deny"]' >"${deny_overlay}"
helm upgrade --install "${release}" chart --namespace "${namespace}" \
  --kube-context "${context}" --values chart/values.lapras.yaml --values "${deny_overlay}" --wait --timeout 5m >/dev/null
wait_for_vap_activation deny
if kubectl --context "${context}" apply -f chart/tests/cases/disallowlatest/bad.yaml 2>/dev/null; then
  echo "❌ deny-mode violating manifest was admitted (expected denied)" >&2
  exit 1
fi

# Local compliance-view half: the targeted apiserver VAP counter increased.
kubectl --context "${context}" get --raw /metrics >"${after_metrics}"
after_count="$(awk '/^apiserver_validating_admission_policy_check_total[{]/ && /policy="vanadium-disallowlatest"/ && /policy_binding="vanadium-disallowlatest"/ && /enforcement_action="warn"/ { sum += $NF } END { print sum + 0 }' "${after_metrics}")"
awk -v before="${before_count}" -v after="${after_count}" 'BEGIN { exit !(after > before) }' || {
  echo "❌ target VAP Warn counter did not increase (${before_count} -> ${after_count})" >&2
  exit 1
}

echo "✅ vanadium k3d install, warn/enforce behavior, and VAP metrics passed"
