#!/usr/bin/env bash
set -euo pipefail

root_dir="$(git rev-parse --show-toplevel)"
cd "${root_dir}"

cluster="goconsumer-$(head -c6 /dev/urandom | od -An -tx1 | tr -d ' \n')"
context="k3d-${cluster}"
cleanup() {
  status=$?
  trap - EXIT
  k3d cluster delete "${cluster}" >/dev/null 2>&1 || true
  rm -rf -- "${root_dir}/infra/root_chart/files" "${root_dir}/infra/primordial_chart/files/observability"
  exit "${status}"
}
trap cleanup EXIT

echo "=== k3d cluster create ${cluster} ==="
k3d cluster create "${cluster}" --servers 1 --agents 0 --image rancher/k3s:v1.31.5-k3s1 \
  --k3s-arg "--disable=traefik@server:*" --no-lb --wait

echo "=== apply test-only CRD fixtures ==="
crd_count="$(find infra/primordial_chart/crds-local -name '*.yaml' -type f | wc -l | tr -d ' ')"
echo "${crd_count} local CRD fixture files"
[ "${crd_count}" -eq 0 ] && echo "❌ no local CRD fixtures found" >&2 && exit 1
kubectl --context "${context}" apply -f infra/primordial_chart/crds-local
kubectl --context "${context}" wait --for=condition=Established --all crd --timeout=2m
established="$(kubectl --context "${context}" get crd -o name | wc -l | tr -d ' ')"
echo "${established} CRDs registered"
[ "${established}" -eq 0 ] && echo "❌ no CRDs registered" >&2 && exit 1

echo "=== build-phase vendoring for both charts ==="
mkdir -p infra/root_chart/files/config infra/primordial_chart/files
cp config/settings.yaml config/*.settings.yaml infra/root_chart/files/config/
if [ -d observability ]; then
  cp -r observability infra/primordial_chart/files/
fi
[ -f infra/primordial_chart/files/problems.json ] || ./scripts/local/problems-export.sh
vendored="$(find infra/root_chart/files infra/primordial_chart/files -type f | wc -l | tr -d ' ')"
echo "${vendored} vendored chart files"
[ "${vendored}" -eq 0 ] && echo "❌ chart vendoring produced no files" >&2 && exit 1

echo "=== install APP chart ==="
helm --kube-context "${context}" upgrade --install go-consumer infra/root_chart \
  --namespace diene --create-namespace \
  --values infra/root_chart/values.lapras.yaml \
  --set image.repository=busybox --set image.tag=1.37.0 \
  --set 'worker.args={sh,-c,while true; do sleep 5; done}' \
  --set 'dbInit.args={sh,-c,echo db-init ok}' \
  --set 'health.command={sh,-c,exit 0}' \
  --set podSecurityContext.runAsUser=0 --set podSecurityContext.runAsGroup=0 \
  --set podSecurityContext.runAsNonRoot=false --set podSecurityContext.fsGroup=null \
  --set containerSecurityContext.readOnlyRootFilesystem=false \
  --wait --timeout=5m

echo "=== install PRIMORDIAL chart into the same cluster ==="
helm --kube-context "${context}" upgrade --install go-consumer-primordial infra/primordial_chart \
  --namespace diene \
  --values infra/primordial_chart/values.lapras.yaml \
  --wait --timeout=5m

echo "=== EVIDENCE: both Helm releases ==="
helm --kube-context "${context}" list --namespace diene
releases="$(helm --kube-context "${context}" list --namespace diene --deployed -o json | jq 'length')"
echo "${releases} deployed releases"
[ "${releases}" -lt 2 ] && echo "❌ expected two deployed releases, found ${releases}" >&2 && exit 1

echo "=== EVIDENCE: app chart workloads ==="
kubectl --context "${context}" --namespace diene get deployment,job,configmap,externalsecret -o name
ready="$(kubectl --context "${context}" --namespace diene get deployment goconsumer-worker -o jsonpath='{.status.readyReplicas}')"
echo "worker readyReplicas ${ready:-0}"
[ "${ready:-0}" -lt 1 ] && echo "❌ worker Deployment never became Ready" >&2 && exit 1
hook="$(kubectl --context "${context}" --namespace diene get job goconsumer-dbinit -o jsonpath='{.status.succeeded}')"
echo "db-init hook Job succeeded ${hook:-0}"
[ "${hook:-0}" -lt 1 ] && echo "❌ db-init pre-sync hook Job never completed" >&2 && exit 1

echo "=== EVIDENCE: dependency-blind rolling worker ==="
kubectl --context "${context}" --namespace diene get deployment goconsumer-worker \
  -o jsonpath='strategy={.spec.strategy.type} liveness={.spec.template.spec.containers[0].livenessProbe.exec.command} readiness={.spec.template.spec.containers[0].readinessProbe.exec.command}{"\n"}'

echo "=== EVIDENCE: primordial T3 custom resources ==="
kubectl --context "${context}" --namespace diene get platformdependency,problem -o name
custom_resources="$(kubectl --context "${context}" --namespace diene get platformdependency,problem -o name | wc -l | tr -d ' ')"
echo "${custom_resources} T3 custom resources admitted"
[ "${custom_resources}" -eq 0 ] && echo "❌ no T3 custom resources were admitted" >&2 && exit 1

echo "✅ both charts installed into cluster ${cluster}"
