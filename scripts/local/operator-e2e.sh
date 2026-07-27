#!/usr/bin/env bash
set -euo pipefail

# Consumers reuse this k3d harness by overriding the chart, values, and image.
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Resolved dynamically so copied consumer harnesses remain relocatable; the helper
# is checked independently by the same shellcheck hook.
# shellcheck disable=SC1091
source "${script_dir}/lib/cluster-name.sh"
# Explicit overrides are honored verbatim; defaults share a unique invocation ID
# so parallel probe sandboxes cannot collide on k3d or Docker resource names.
invocation_id="$(e2e_invocation_id "${script_dir}" "$$")"
cluster="$(e2e_cluster_name "${CLUSTER:-}" "${invocation_id}")"
chart="${CHART:-infra/root_chart}"
values="${VALUES:-infra/root_chart/values.lapras.yaml}"
image="$(e2e_image_name "${IMAGE:-}" "${invocation_id}")"
timeout="${TIMEOUT:-180s}"
namespace="${NAMESPACE:-fleet-operator}"
release="${RELEASE:-fleet-operator}"
remove_default_image=false
[[ -z ${IMAGE:-} ]] && remove_default_image=true

kubeconfig_dir="$(mktemp -d "${TMPDIR:-/tmp}/operator-e2e-${invocation_id}.XXXXXX")"
kubeconfig="${kubeconfig_dir}/kubeconfig"

cleanup() {
  k3d cluster delete "${cluster}" >/dev/null 2>&1 || true
  if [[ ${remove_default_image} == true ]]; then
    docker image rm "${image}" >/dev/null 2>&1 || true
  fi
  rm -f -- "${kubeconfig}"
  rmdir -- "${kubeconfig_dir}" 2>/dev/null || true
}
trap cleanup EXIT

if [[ ${image} == *@* ]]; then
  echo "❌ IMAGE digest references are unsupported by this tag-based harness: ${image}" >&2
  exit 2
fi

image_basename="${image##*/}"
if [[ ${image_basename} == *:* ]]; then
  image_tag="${image_basename##*:}"
  image_repository="${image%:"${image_tag}"}"
else
  image_repository="${image}"
  image_tag="latest"
fi

expected_crds=(
  cloudflaredeploys.fleet.atomi.cloud
  clusterregistrations.fleet.atomi.cloud
  decommissions.fleet.atomi.cloud
  landscapes.fleet.atomi.cloud
  platformdependencies.fleet.atomi.cloud
  platforms.fleet.atomi.cloud
  problems.atomi.cloud
  provideraccounts.fleet.atomi.cloud
  virtuallandscapes.fleet.atomi.cloud
  virtuallandscapeservices.fleet.atomi.cloud
  webhookengines.fleet.atomi.cloud
  webhookroutes.fleet.atomi.cloud
)

echo "🔨 Creating k3d cluster ${cluster}"
k3d cluster create "${cluster}" \
  --kubeconfig-update-default=false \
  --kubeconfig-switch-context=false \
  --wait --timeout "${timeout}"
k3d kubeconfig get "${cluster}" >"${kubeconfig}"
export KUBECONFIG="${kubeconfig}"

echo "📦 Building and importing manager image ${image}"
docker build -f infra/Dockerfile -t "${image}" .
k3d image import "${image}" -c "${cluster}"

kubectl create namespace "${namespace}" --dry-run=client -o yaml | kubectl apply -f -

echo "📦 Installing the all-disabled observe-mode manager chart"
helm install "${release}" "${chart}" -n "${namespace}" -f "${values}" \
  --set image.repository="${image_repository}" \
  --set image.tag="${image_tag}" \
  --set image.pullPolicy=IfNotPresent \
  --set serviceMonitor.enabled=false \
  --set alerts.enabled=false \
  --set dashboard.enabled=false \
  --set mode=observe \
  --set controllers.cluster=false \
  --set controllers.platform=false \
  --set controllers.dependency=false \
  --set controllers.traffic=false \
  --set controllers.webhook=false \
  --set controllers.cf-deploy=false \
  --set controllers.problem=false \
  --wait --timeout "${timeout}"

mapfile -t actual_crds < <(kubectl get customresourcedefinitions -o name | sed 's|^customresourcedefinition.apiextensions.k8s.io/||' | sort)
if [[ ${#actual_crds[@]} -ne ${#expected_crds[@]} ]]; then
  printf 'expected CRDs:\n%s\nactual CRDs:\n%s\n' "$(printf '%s\n' "${expected_crds[@]}")" "$(printf '%s\n' "${actual_crds[@]}")" >&2
  exit 1
fi
for index in "${!expected_crds[@]}"; do
  if [[ ${actual_crds[index]} != "${expected_crds[index]}" ]]; then
    echo "❌ CRD set differs at index ${index}: expected ${expected_crds[index]}, got ${actual_crds[index]}" >&2
    exit 1
  fi
done
for crd in "${expected_crds[@]}"; do
  kubectl wait --for=condition=Established --timeout "${timeout}" "customresourcedefinition/${crd}"
done

kubectl rollout status -n "${namespace}" "deploy/${release}" --timeout "${timeout}"
pod="$(kubectl get pods -n "${namespace}" -l "app.kubernetes.io/instance=${release}" -o jsonpath='{.items[0].metadata.name}')"
if [[ -z ${pod} ]]; then
  echo "❌ manager pod was not created" >&2
  exit 1
fi
health="$(kubectl get --raw "/api/v1/namespaces/${namespace}/pods/${pod}:8081/proxy/healthz")"
if [[ ${health} != "ok" ]]; then
  echo "❌ manager /healthz returned '${health}'" >&2
  exit 1
fi
ready="$(kubectl get --raw "/api/v1/namespaces/${namespace}/pods/${pod}:8081/proxy/readyz")"
if [[ ${ready} != "ok" ]]; then
  echo "❌ manager /readyz returned '${ready}'" >&2
  exit 1
fi

args="$(kubectl get deployment -n "${namespace}" "${release}" -o json | jq -r '.spec.template.spec.containers[0].args[]')"
if ! rg -qx -- '--observe=true' <<<"${args}"; then
  echo "❌ manager did not start in observe mode" >&2
  exit 1
fi
for controller in cluster platform dependency traffic webhook cf-deploy problem; do
  if ! rg -qx -- "--enable-${controller}=false" <<<"${args}"; then
    echo "❌ controller ${controller} was not explicitly disabled" >&2
    exit 1
  fi
done

echo "✅ Operator k3d skeleton passed: 12 CRDs Established, all controllers disabled, observe-mode manager healthy"
