#!/usr/bin/env bash
set -euo pipefail

# Consumers reuse this k3d harness by overriding the chart, values, fixtures, and image.
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
note_fixture="${NOTE_FIXTURE:-${FIXTURE:-tests/fixtures/operator/valid-note.yaml}}"
image="$(e2e_image_name "${IMAGE:-}" "${invocation_id}")"
timeout="${TIMEOUT:-180s}"
namespace="${NAMESPACE:-fleet-operator}"
release="${RELEASE:-fleet-operator}"
remove_default_image=false
[ -z "${IMAGE:-}" ] && remove_default_image=true

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

note_name="$(yq -r '.metadata.name // ""' "${note_fixture}")"
[ -z "${note_name}" ] && echo "❌ Note fixture has no metadata.name: ${note_fixture}" >&2 && exit 2
expected_copies="${EXPECTED_COPIES:-$(yq -r '.spec.replicas // 1' "${note_fixture}")}"

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

echo "📦 Deploying the MinIO ledger"
kubectl apply -n "${namespace}" -f - <<'MINIO'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: minio
spec:
  replicas: 1
  selector:
    matchLabels: { app: minio }
  template:
    metadata:
      labels: { app: minio }
    spec:
      containers:
        - name: minio
          image: minio/minio:RELEASE.2024-01-16T16-07-38Z
          args: ["server", "/data"]
          env:
            - { name: MINIO_ROOT_USER, value: minioadmin }
            - { name: MINIO_ROOT_PASSWORD, value: minioadmin }
          ports:
            - containerPort: 9000
---
apiVersion: v1
kind: Service
metadata:
  name: minio
spec:
  selector: { app: minio }
  ports:
    - port: 9000
      targetPort: 9000
MINIO
kubectl rollout status -n "${namespace}" deploy/minio --timeout "${timeout}"
kubectl create secret generic "${release}-ledger" -n "${namespace}" --from-literal=accessKey=minioadmin --from-literal=secretKey=minioadmin --dry-run=client -o yaml | kubectl apply -f -

echo "📦 Installing the manager chart"
helm install "${release}" "${chart}" -n "${namespace}" -f "${values}" \
  --set image.repository="${image_repository}" \
  --set image.tag="${image_tag}" \
  --set image.pullPolicy=IfNotPresent \
  --set serviceMonitor.enabled=false \
  --set alerts.enabled=false \
  --set dashboard.enabled=false \
  --set controllers.note=true \
  --set controllers.journal=true \
  --set ledger.endpoint=minio:9000 \
  --set ledger.secure=false \
  --wait --timeout "${timeout}"
kubectl rollout status -n "${namespace}" "deploy/${release}" --timeout "${timeout}"

pod="$(kubectl get pods -n "${namespace}" -l "app.kubernetes.io/instance=${release}" -o jsonpath='{.items[0].metadata.name}')"
[ -z "${pod}" ] && echo "❌ manager pod was not created" >&2 && exit 1
health="$(kubectl get --raw "/api/v1/namespaces/${namespace}/pods/${pod}:8081/proxy/healthz")"
[ "${health}" != "ok" ] && echo "❌ manager /healthz returned '${health}'" >&2 && exit 1
ready="$(kubectl get --raw "/api/v1/namespaces/${namespace}/pods/${pod}:8081/proxy/readyz")"
[ "${ready}" != "ok" ] && echo "❌ manager /readyz returned '${ready}'" >&2 && exit 1

echo "🧪 Applying Note and Journal fixtures"
kubectl apply -n "${namespace}" -f "${note_fixture}"
kubectl apply -n "${namespace}" -f - <<'JOURNAL'
apiVersion: sample.diene.atomi.cloud/v1alpha1
kind: Journal
metadata:
  name: harness-journal
spec:
  message: converged by the k3d harness
JOURNAL
kubectl wait -n "${namespace}" --for=condition=Ready --timeout "${timeout}" "note/${note_name}"
kubectl wait -n "${namespace}" --for=condition=Ready --timeout "${timeout}" journal/harness-journal

copies="$(kubectl get configmaps -n "${namespace}" -l "fleet-operator.diene.atomi.cloud/note=${note_name}" -o name | wc -l | tr -d ' ')"
[ "${copies}" -ne "${expected_copies}" ] && echo "❌ expected ${expected_copies} owned ConfigMaps, found ${copies}" >&2 && exit 1

echo "✅ Operator k3d e2e passed: manager healthy, Note and Journal Ready, ${copies} owned ConfigMaps"
