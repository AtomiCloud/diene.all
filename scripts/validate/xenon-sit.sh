#!/usr/bin/env bash
# Xenon integration / SIT tier (edge chart, Q-I32). RESERVED for orchestration
# authorization on an enabled cloud/on-prem context; never run on k3d/lapras.
set -euo pipefail

context="${SIT_CONTEXT:-}"
namespace="${SIT_NAMESPACE:-}"
release="${RELEASE:-}"
evidence_input="${SIT_EVIDENCE_DIR:-}"
values_input="${SIT_VALUES_FILE:-}"

[ -z "${context}" ] && echo "❌ SIT_CONTEXT (an enabled cloud/on-prem kubeconfig context) is required" >&2 && exit 1
[ -z "${namespace}" ] && echo "❌ SIT_NAMESPACE is required" >&2 && exit 1
[ -z "${release}" ] && echo "❌ RELEASE is required" >&2 && exit 1
[ -z "${evidence_input}" ] && echo "❌ SIT_EVIDENCE_DIR is required" >&2 && exit 1
[ -z "${values_input}" ] && echo "❌ SIT_VALUES_FILE (an authoritative ON stack) is required" >&2 && exit 1
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
toggle_map="$(realpath chart/toggle-map.yaml)"
if ! values_file="$(realpath "${values_input}")"; then
  echo "❌ SIT_VALUES_FILE does not resolve to a file: ${values_input}" >&2
  exit 1
fi
run_status=0
cleanup_status=0
exec > >(tee "${evidence_dir}/sit.stdout") 2> >(tee "${evidence_dir}/sit.stderr" >&2)

trap 'run_status=$?; trap - EXIT; cleanup_status=0; SIT_CONTEXT="${context}" SIT_NAMESPACE="${namespace}" RELEASE="${release}" SIT_EVIDENCE_DIR="${evidence_dir}" bash ./scripts/validate/xenon-sit-cleanup.sh || cleanup_status=$?; if [ "${cleanup_status}" -ne 0 ]; then echo "❌ Xenon SIT cleanup failed; evidence is in ${evidence_dir}" >&2; exit "${cleanup_status}"; fi; if [ "${run_status}" -eq 0 ]; then echo "✅ Xenon SIT behavior and cleanup proof complete; evidence is in ${evidence_dir}"; fi; exit "${run_status}"' EXIT

matrix_json="$(yq -o=json '.' "${toggle_map}")"
matched_landscapes=()
while IFS=$'\t' read -r candidate_landscape candidate_overlay; do
  candidate_file="$(realpath "${candidate_overlay}")"
  if [ "${candidate_file}" = "${values_file}" ]; then
    matched_landscapes+=("${candidate_landscape}")
  fi
done < <(printf '%s' "${matrix_json}" | jq -r '.landscapes[] | select(.enabled == true and (.overlays | length) == 1) | [.landscape, .overlays[0]] | @tsv')

if [ "${#matched_landscapes[@]}" -ne 1 ]; then
  echo "❌ SIT_VALUES_FILE must resolve to exactly one authoritative toggle-map ON stack: ${values_file}" >&2
  exit 1
fi
landscape="${matched_landscapes[0]}"
if ! printf '%s' "${matrix_json}" | jq -e --arg landscape "${landscape}" '
  [.providers[] | select(.landscapes | index($landscape))] as $providers
  | ($providers | length) > 0
    and all($providers[]; .enabled == true and .preinstalled == false)
' >/dev/null; then
  echo "❌ SIT_VALUES_FILE is not enabled by every authoritative provider row for ${landscape}" >&2
  exit 1
fi

if ! yq eval-all -o=json 'select(fileIndex == 0) * select(fileIndex == 1)' "${chart_dir}/values.yaml" "${values_file}" \
  >"${evidence_dir}/preflight-values.json"; then
  echo "❌ could not resolve the effective SIT values" >&2
  exit 1
fi
if ! jq -e '.metricsServer.enabled == true' "${evidence_dir}/preflight-values.json" >/dev/null; then
  echo "❌ authoritative SIT stack must resolve metricsServer.enabled=true" >&2
  exit 1
fi

label_prefix="$(jq -er '.global.labelPrefix | strings | select(length > 0)' "${evidence_dir}/preflight-values.json")"
ownership_label_key="${label_prefix}/sit-run-id"
escaped_label_key="${ownership_label_key//./\\.}"
run_id="xenon-sit-$(uuidgen | tr '[:upper:]' '[:lower:]')"
printf '%s' "${run_id}" | rg -q '^xenon-sit-[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
resource_label_set="metricsServer.commonLabels.${escaped_label_key}=${run_id}"
pod_label_set="metricsServer.podLabels.${escaped_label_key}=${run_id}"

jq -n \
  --arg context "${context}" \
  --arg namespace "${namespace}" \
  --arg release "${release}" \
  --arg chart "${chart_dir}" \
  --arg values "${values_file}" \
  --arg toggleMap "${toggle_map}" \
  --arg landscape "${landscape}" \
  --arg runId "${run_id}" \
  --arg labelKey "${ownership_label_key}" \
  '{context: $context, namespace: $namespace, release: $release, chart: $chart, values: $values, toggleMap: $toggleMap, landscape: $landscape, runId: $runId, ownershipLabel: {key: $labelKey, value: $runId}}' \
  >"${evidence_dir}/inputs.json"

if ! helm template "${release}" "${chart_dir}" --namespace "${namespace}" --values "${values_file}" \
  --labels "${ownership_label_key}=${run_id}" \
  --set-string "${resource_label_set}" \
  --set-string "${pod_label_set}" \
  > >(tee "${evidence_dir}/preflight-render.yaml") \
  2> >(tee "${evidence_dir}/preflight-render.stderr" >&2); then
  echo "❌ authoritative ON stack did not render successfully" >&2
  exit 1
fi
if ! yq eval-all -o=json '.' "${evidence_dir}/preflight-render.yaml" | jq -se --arg key "${ownership_label_key}" --arg runId "${run_id}" '
  map(select(type == "object" and .kind == "Deployment" and .metadata.name == "xenon-metrics"))
  | length == 1
    and .[0].metadata.labels[$key] == $runId
    and .[0].spec.template.metadata.labels[$key] == $runId
' >/dev/null; then
  echo "❌ ON-stack render is missing the run-specific resource metadata" >&2
  exit 1
fi

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
jq -n \
  --arg context "${context}" \
  --arg namespace "${namespace}" \
  --arg release "${release}" \
  --arg runId "${run_id}" \
  --arg labelKey "${ownership_label_key}" \
  '{context: $context, namespace: $namespace, release: $release, runId: $runId, ownershipLabel: {key: $labelKey, value: $runId}}' \
  >"${evidence_dir}/ownership.claim"

if ! helm install "${release}" "${chart_dir}" --kube-context "${context}" --namespace "${namespace}" --create-namespace \
  --values "${values_file}" \
  --labels "${ownership_label_key}=${run_id}" \
  --set-string "${resource_label_set}" \
  --set-string "${pod_label_set}" \
  --atomic --wait --timeout 5m \
  > >(tee "${evidence_dir}/helm-install.stdout") \
  2> >(tee "${evidence_dir}/helm-install.stderr" >&2); then
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
