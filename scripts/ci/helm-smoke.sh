#!/usr/bin/env bash
set -euo pipefail

# Throwaway-cluster install smoke. `helm template` proves the charts RENDER;
# only a real apiserver proves they INSTALL — admission, the kubeVersion floor,
# and the ClusterIP wiring are invisible to templating.
#
# Called by scripts/ci/helm.sh only when k3d, kubectl, and a live docker daemon
# are all present. Runnable standalone for local iteration.

cluster="diene-helm-smoke-$$"
# k3d's default k3s image is far below the charts' `kubeVersion: >=1.27.0-0`
# floor, so the image is pinned rather than inherited.
k3s_image="rancher/k3s:v1.31.5-k3s1"
namespace="helm-smoke"

chart_primordial="infra/primordial_chart"
chart_garden="infra/garden_app_chart"

cleanup() {
  echo "🧹 Tearing down ${cluster}..."
  k3d cluster delete "${cluster}" >/dev/null 2>&1 || true
}
trap cleanup EXIT

echo "🚀 Creating throwaway cluster ${cluster} (${k3s_image})..."
k3d cluster create "${cluster}" --image "${k3s_image}" --wait >/dev/null

kubectl create namespace "${namespace}" >/dev/null

# The primordial chart emits operator CRs (Grafana*, LogtoApp,
# PlatformDependency) whose operators are not installed here. Minimal
# preserve-unknown-fields CRDs make the install a real server-side apply
# instead of a dry run, without dragging three operators into CI.
#
# The group/version/kind set is READ OUT OF THE RENDER rather than hardcoded:
# `dependencyApiVersion` is a chart value (R21), so a hardcoded list here would
# silently stop covering the chart the moment someone repoints it.
echo "📐 Registering placeholder CRDs for the dependency operators..."
while IFS=' ' read -r api_version kind; do
  [ -z "${kind}" ] && continue
  group="${api_version%%/*}"
  version="${api_version##*/}"
  # Only cluster-foreign kinds need a stub; core/apps objects already exist.
  case "${group}" in
  '' | v1 | apps | batch | networking.k8s.io) continue ;;
  esac
  singular="${kind,,}"
  case "${singular}" in
  *y) plural="${singular%y}ies" ;;
  *s | *x | *ch | *sh) plural="${singular}es" ;;
  *) plural="${singular}s" ;;
  esac
  kubectl apply -f - >/dev/null <<EOF
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  name: ${plural}.${group}
spec:
  group: ${group}
  scope: Namespaced
  names:
    plural: ${plural}
    singular: ${singular}
    kind: ${kind}
  versions:
    - name: ${version}
      served: true
      storage: true
      schema:
        openAPIV3Schema:
          type: object
          x-kubernetes-preserve-unknown-fields: true
EOF
  echo "  📐 ${group}/${version} ${kind}"
done < <(helm template primordial "${chart_primordial}" |
  yq -r 'select(.kind) | .apiVersion + " " + .kind' | sort -u)

echo "📦 Installing the primordial chart..."
helm install primordial "${chart_primordial}" -n "${namespace}" --wait --timeout 5m >/dev/null

# A stand-in image keeps this rail independent of an app build: the point is to
# prove the CHART installs and wires, not to re-test the Next.js server (the e2e
# and image-smoke rails already do that). nginx-unprivileged is chosen because it
# runs as nonroot on a read-only rootfs — it satisfies the same securityContext
# the chart pins, so the pod really does exercise those constraints.
#
# `runtime.port` (not a workload key) is what drives containerPort; health.path
# is single and shared. Both schemas are sealed, so a wrong key here fails loudly
# rather than being silently dropped.
echo "📦 Installing the Garden app chart (ditto profile)..."
helm install garden "${chart_garden}" \
  -n "${namespace}" \
  -f "${chart_garden}/profiles/ditto.yaml" \
  --set image.repository=nginxinc/nginx-unprivileged \
  --set image.tag=1.27-alpine \
  --set runtime.port=8080 \
  --set service.port=8080 \
  --set health.path=/ \
  --wait --timeout 8m >/dev/null

echo "🔎 Asserting the release owns only its workload objects..."
kinds="$(helm get manifest garden -n "${namespace}" | grep '^kind:' | sed 's/^kind:[[:space:]]*//' | sort -u)"
while IFS= read -r kind; do
  [ -z "${kind}" ] && continue
  case "${kind}" in
  Deployment | Service | ServiceAccount) ;;
  *)
    echo "❌ installed release contains unowned object '${kind}'" >&2
    exit 1
    ;;
  esac
done <<<"${kinds}"

kubectl -n "${namespace}" rollout status deployment -l app.kubernetes.io/instance=garden --timeout=3m

echo "🌐 Probing the ClusterIP Service from inside the cluster..."
svc="$(kubectl -n "${namespace}" get svc -l app.kubernetes.io/instance=garden -o jsonpath='{.items[0].metadata.name}')"
port="$(kubectl -n "${namespace}" get svc "${svc}" -o jsonpath='{.spec.ports[0].port}')"
# Run detached and read the logs afterwards. Attaching races the container:
# a fast curl can exit before the stream is established, which makes kubectl
# fall back to log streaming and print the status code twice.
kubectl -n "${namespace}" run smoke-probe \
  --image=curlimages/curl:8.11.1 \
  --restart=Never --quiet --attach=false \
  --command -- curl -fsS --max-time 20 -o /dev/null -w '%{http_code}' \
  "http://${svc}:${port}/" >/dev/null
kubectl -n "${namespace}" wait --for=jsonpath='{.status.phase}'=Succeeded pod/smoke-probe --timeout=90s >/dev/null
status="$(kubectl -n "${namespace}" logs pod/smoke-probe | tr -d '[:space:]')"
kubectl -n "${namespace}" delete pod smoke-probe --wait=false >/dev/null 2>&1 || true

[ "${status}" = "200" ] || {
  echo "❌ ClusterIP probe returned '${status}', want 200" >&2
  exit 1
}
echo "  ✅ HTTP ${status} via ${svc}:${port}"

echo "✅ Helm install smoke green"
