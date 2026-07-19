#!/usr/bin/env bash
# Xenon integration / SIT tier (edge chart, Q-I32). RESERVED for orchestration
# authorization on an enabled cloud/on-prem context; never run on k3d/lapras.
set -euo pipefail

context="${SIT_CONTEXT:-}"
namespace="${SIT_NAMESPACE:-}"
release="${RELEASE:-}"
evidence_input="${SIT_EVIDENCE_DIR:-}"
values_input="${SIT_VALUES_FILE:-chart/values.pichu.yaml}"

[ -z "${context}" ] && echo "❌ SIT_CONTEXT (an enabled cloud/on-prem kubeconfig context) is required" >&2 && exit 1
[ -z "${namespace}" ] && echo "❌ SIT_NAMESPACE is required" >&2 && exit 1
[ -z "${release}" ] && echo "❌ RELEASE is required" >&2 && exit 1
[ -z "${evidence_input}" ] && echo "❌ SIT_EVIDENCE_DIR is required" >&2 && exit 1
case "${evidence_input}" in /*) ;; *)
  echo "❌ SIT_EVIDENCE_DIR must be absolute" >&2
  exit 1
  ;;
esac
printf '%s' "${namespace}" | rg -q '^[a-z0-9]([-a-z0-9]*[a-z0-9])?$'
printf '%s' "${release}" | rg -q '^[a-z0-9]([-a-z0-9]*[a-z0-9])?$'

mkdir -p "${evidence_input}"
evidence_dir="$(realpath "${evidence_input}")"
[ -n "$(find "${evidence_dir}" -mindepth 1 -maxdepth 1 -print -quit)" ] && echo "❌ SIT_EVIDENCE_DIR must be empty: ${evidence_dir}" >&2 && exit 1
chart_dir="$(realpath chart)"
values_file="$(realpath "${values_input}")"
run_status=0
cleanup_status=0
exec > >(tee "${evidence_dir}/sit.stdout") 2> >(tee "${evidence_dir}/sit.stderr" >&2)

trap 'run_status=$?; trap - EXIT; cleanup_status=0; SIT_CONTEXT="${context}" SIT_NAMESPACE="${namespace}" RELEASE="${release}" SIT_EVIDENCE_DIR="${evidence_dir}" bash ./scripts/validate/xenon-sit-cleanup.sh || cleanup_status=$?; if [ "${cleanup_status}" -ne 0 ]; then echo "❌ Xenon SIT cleanup failed; evidence is in ${evidence_dir}" >&2; exit "${cleanup_status}"; fi; if [ "${run_status}" -eq 0 ]; then echo "✅ Xenon SIT behavior and cleanup proof complete; evidence is in ${evidence_dir}"; fi; exit "${run_status}"' EXIT

jq -n --arg context "${context}" --arg namespace "${namespace}" --arg release "${release}" --arg chart "${chart_dir}" --arg values "${values_file}" \
  '{context: $context, namespace: $namespace, release: $release, chart: $chart, values: $values}' >"${evidence_dir}/inputs.json"

if ! helm list --all --kube-context "${context}" --namespace "${namespace}" --filter "^${release}$" --output json \
  > >(tee "${evidence_dir}/preflight-list.stdout.json") \
  2> >(tee "${evidence_dir}/preflight-list.stderr" >&2); then
  echo "❌ preflight could not inspect the target release" >&2
  exit 1
fi
if ! jq -e 'length == 0' "${evidence_dir}/preflight-list.stdout.json" >/dev/null; then
  echo "❌ release ${release} already exists; refusing to mutate or uninstall an unowned release" >&2
  exit 1
fi
printf 'context=%s\nnamespace=%s\nrelease=%s\n' "${context}" "${namespace}" "${release}" >"${evidence_dir}/ownership.claim"

if ! helm upgrade --install "${release}" "${chart_dir}" --kube-context "${context}" --namespace "${namespace}" --create-namespace \
  --values "${values_file}" --atomic --cleanup-on-fail --wait --timeout 5m \
  > >(tee "${evidence_dir}/helm-upgrade.stdout") \
  2> >(tee "${evidence_dir}/helm-upgrade.stderr" >&2); then
  echo "❌ atomic Helm install failed" >&2
  exit 1
fi

if ! kubectl --context "${context}" --namespace "${namespace}" rollout status deployment/xenon-metrics --timeout 5m \
  > >(tee "${evidence_dir}/rollout.stdout") \
  2> >(tee "${evidence_dir}/rollout.stderr" >&2); then
  echo "❌ metrics-server rollout failed" >&2
  exit 1
fi

if ! helm status "${release}" --kube-context "${context}" --namespace "${namespace}" --output json \
  > >(tee "${evidence_dir}/helm-status.json") \
  2> >(tee "${evidence_dir}/helm-status.stderr" >&2); then
  echo "❌ Helm status capture failed" >&2
  exit 1
fi
jq -e '.info.status == "deployed"' "${evidence_dir}/helm-status.json" >/dev/null

if ! kubectl --context "${context}" top nodes \
  > >(tee "${evidence_dir}/top-nodes.stdout") \
  2> >(tee "${evidence_dir}/top-nodes.stderr" >&2); then
  echo "❌ kubectl top nodes failed" >&2
  exit 1
fi
if ! kubectl --context "${context}" --namespace "${namespace}" top pods \
  > >(tee "${evidence_dir}/top-pods.stdout") \
  2> >(tee "${evidence_dir}/top-pods.stderr" >&2); then
  echo "❌ kubectl top pods failed" >&2
  exit 1
fi
awk 'NR > 1 { found = 1 } END { exit !found }' "${evidence_dir}/top-nodes.stdout"
awk 'NR > 1 { found = 1 } END { exit !found }' "${evidence_dir}/top-pods.stdout"

echo "✅ Xenon SIT behavior assertions passed; ownership-safe cleanup is pending"
