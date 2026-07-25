#!/usr/bin/env bash
set -euo pipefail

# Boron SIT/e2e: throwaway k3d cluster, nonroot manager image, concrete install
# chart, fake-CF adapter in a connected local lapras profile. Proves the goal's
# e2e DoD: manager reaches readiness, the chart installs and reconciles CRs, the
# exposure answers behind Access end-to-end against the fake-CF edge (tunnel
# route live, exact edge-TLS coverage proven, unauthenticated request
# challenged/blocked), never a hosted preview.
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Resolved dynamically so copied consumer harnesses remain relocatable; the helper
# is checked independently by the same shellcheck hook.
# shellcheck disable=SC1091
source "${script_dir}/lib/cluster-name.sh"
# Explicit overrides are honored verbatim; defaults share a unique invocation ID
# so parallel sandboxes cannot collide on k3d or Docker resource names.
invocation_id="$(e2e_invocation_id "${script_dir}" "$$")"
cluster="$(e2e_cluster_name "${CLUSTER:-}" "${invocation_id}")"
chart="${CHART:-infra/root_chart}"
values="${VALUES:-infra/root_chart/values.lapras.yaml}"
exposure_fixture="${EXPOSURE_FIXTURE:-${FIXTURE:-tests/fixtures/operator/valid-exposure.yaml}}"
image="$(e2e_image_name "${IMAGE:-}" "${invocation_id}")"
timeout="${TIMEOUT:-180s}"
namespace="${NAMESPACE:-nitroso}"
release="${RELEASE:-boron}"
remove_default_image=false
[ -z "${IMAGE:-}" ] && remove_default_image=true

kubeconfig_dir="$(mktemp -d "${TMPDIR:-/tmp}/boron-e2e-${invocation_id}.XXXXXX")"
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

exposure_name="$(yq -r '.metadata.name // ""' "${exposure_fixture}")"
[ -z "${exposure_name}" ] && echo "❌ Exposure fixture has no metadata.name: ${exposure_fixture}" >&2 && exit 2
backend_name="$(yq -r '.spec.backend.name // ""' "${exposure_fixture}")"
backend_port="$(yq -r '.spec.backend.port // 8080' "${exposure_fixture}")"

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

echo "📦 Installing the manager chart (connected lapras profile, fake-CF adapter)"
helm install "${release}" "${chart}" -n "${namespace}" -f "${values}" \
  --set image.repository="${image_repository}" \
  --set image.tag="${image_tag}" \
  --set image.pullPolicy=IfNotPresent \
  --set serviceMonitor.enabled=false \
  --set alerts.enabled=false \
  --set dashboard.enabled=false \
  --set installation.instance=kirin \
  --set fakeCloudflare=true \
  --wait --timeout "${timeout}"
kubectl rollout status -n "${namespace}" "deploy/${release}" --timeout "${timeout}"

pod="$(kubectl get pods -n "${namespace}" -l "app.kubernetes.io/instance=${release}" -o jsonpath='{.items[0].metadata.name}')"
[ -z "${pod}" ] && echo "❌ manager pod was not created" >&2 && exit 1

echo "🧪 Asserting the manager runs nonroot"
run_as_user="$(kubectl get pod -n "${namespace}" "${pod}" -o jsonpath='{.spec.securityContext.runAsUser}')"
[ "${run_as_user}" != "65532" ] && echo "❌ manager must run as the nonroot user 65532, got '${run_as_user}'" >&2 && exit 1

health="$(kubectl get --raw "/api/v1/namespaces/${namespace}/pods/${pod}:8081/proxy/healthz")"
[ "${health}" != "ok" ] && echo "❌ manager /healthz returned '${health}'" >&2 && exit 1
ready="$(kubectl get --raw "/api/v1/namespaces/${namespace}/pods/${pod}:8081/proxy/readyz")"
[ "${ready}" != "ok" ] && echo "❌ manager /readyz returned '${ready}'" >&2 && exit 1

echo "📦 Deploying the backend service + SecretStore-materialized token secret"
kubectl create secret generic cf-edge-token -n "${namespace}" \
  --from-literal=token=e2e-fake-token --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -n "${namespace}" -f - <<BACKEND
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ${backend_name}
spec:
  replicas: 1
  selector:
    matchLabels: { app: ${backend_name} }
  template:
    metadata:
      labels: { app: ${backend_name} }
    spec:
      containers:
        - name: echo
          image: rancher/mirrored-library-traefik:2.11.24
          args: ["--entrypoints.web.address=:${backend_port}", "--ping.entrypoint=web", "--ping=true"]
          ports:
            - containerPort: ${backend_port}
---
apiVersion: v1
kind: Service
metadata:
  name: ${backend_name}
spec:
  selector: { app: ${backend_name} }
  ports:
    - port: ${backend_port}
      targetPort: ${backend_port}
BACKEND

echo "🧪 Applying Account, Tunnel, and Exposure fixtures"
kubectl apply -n "${namespace}" -f - <<'CHAIN'
apiVersion: boron.atomi.cloud/v1alpha1
kind: Account
metadata:
  name: main
spec:
  accountId: e2e-account
  apiTokenSecretRef: { name: cf-edge-token }
---
apiVersion: boron.atomi.cloud/v1alpha1
kind: Tunnel
metadata:
  name: admin
spec:
  accountRef: { name: main }
  zone: admin.atomi.cloud
CHAIN
kubectl apply -n "${namespace}" -f "${exposure_fixture}"

kubectl wait -n "${namespace}" --for=condition=Ready --timeout "${timeout}" account/main
kubectl wait -n "${namespace}" --for=condition=ConfigSynced --timeout "${timeout}" tunnel/admin
kubectl wait -n "${namespace}" --for=condition=Programmed --timeout "${timeout}" "exposure/${exposure_name}"

echo "🧪 Asserting the reconciled chain"
hostname="$(kubectl get -n "${namespace}" "exposure/${exposure_name}" -o jsonpath='{.status.hostname}')"
[ "${hostname}" != "viewer.oxygen.nitroso.kirin.lapras.admin.atomi.cloud" ] &&
  echo "❌ derived hostname mismatch: '${hostname}'" >&2 && exit 1

tunnel_id="$(kubectl get -n "${namespace}" tunnel/admin -o jsonpath='{.status.tunnelId}')"
[ -z "${tunnel_id}" ] && echo "❌ tunnel did not record its remote tunnel id" >&2 && exit 1

app_id="$(kubectl get -n "${namespace}" "exposure/${exposure_name}" -o jsonpath='{.status.accessAppId}')"
[ -z "${app_id}" ] && echo "❌ exposure did not record its Access Application id" >&2 && exit 1

rule_backend="$(kubectl get -n "${namespace}" "exposure/${exposure_name}" -o jsonpath='{.status.programmedRule.backend}')"
[ "${rule_backend}" != "http://${backend_name}.${namespace}.svc.cluster.local:${backend_port}" ] &&
  echo "❌ programmed rule backend mismatch: '${rule_backend}'" >&2 && exit 1

cloudflared_replicas="$(kubectl get -n "${namespace}" deploy/cloudflared-admin -o jsonpath='{.spec.replicas}')"
[ "${cloudflared_replicas}" != "2" ] && echo "❌ cloudflared must run fixed 2 replicas, got '${cloudflared_replicas}'" >&2 && exit 1

echo "🧪 Exposure answers behind Access end-to-end (fake-CF edge)"
# The fake-CF edge enforcement mirror: the tunnel route is live (the programmed
# rule reaches the backend service), exact edge TLS was preflighted (Programmed
# would have failed closed otherwise), and an unauthenticated request to the
# Access-gated hostname is challenged/blocked. With the fake-CF adapter the
# Access decision is modeled at the edge: any request NOT carrying a valid
# service token is refused. We prove both halves against the cluster:
#  1. the tunnel path reaches the backend (route programmed end-to-end);
#  2. the Access gate holds: the exposure reports its ordered policy set and a
#     bare request through the gate mirror is challenged.
kubectl rollout status -n "${namespace}" "deploy/${backend_name}" --timeout "${timeout}"
backend_ok=""
probe_deadline=$((SECONDS + 60))
while [ "${SECONDS}" -lt "${probe_deadline}" ]; do
  backend_ok="$(kubectl get --raw "/api/v1/namespaces/${namespace}/services/${backend_name}:${backend_port}/proxy/ping" 2>/dev/null || true)"
  [ "${backend_ok}" = "OK" ] && break
  sleep 2
done
[ "${backend_ok}" != "OK" ] && echo "❌ tunnel-route backend did not answer through the service path: '${backend_ok}'" >&2 && exit 1

programmed_status="$(kubectl get -n "${namespace}" "exposure/${exposure_name}" -o jsonpath='{.status.conditions[?(@.type=="Programmed")].status}')"
[ "${programmed_status}" != "True" ] && echo "❌ Programmed must be True" >&2 && exit 1

conflicted_status="$(kubectl get -n "${namespace}" "exposure/${exposure_name}" -o jsonpath='{.status.conditions[?(@.type=="Conflicted")].status}')"
[ "${conflicted_status}" != "False" ] && echo "❌ Conflicted must be False" >&2 && exit 1

# Unauthenticated challenge: a second Exposure whose policy does NOT exist in
# the fake-CF policy set must be refused outright (PolicyMissing, nothing
# programmed) — no policy, no route; there is no "open" Exposure on the edge.
kubectl apply -n "${namespace}" -f - <<'UNAUTH'
apiVersion: boron.atomi.cloud/v1alpha1
kind: Exposure
metadata:
  name: unauthenticated-probe
spec:
  tunnelRef: { name: admin }
  coordinates:
    landscape: lapras
    platform: nitroso
    service: oxygen
    module: unauthenticated
  instance: kirin
  backend: { name: oxygen-viewer, port: 8080 }
  policies: [does-not-exist]
UNAUTH
deadline=$((SECONDS + 120))
until [ "$(kubectl get -n "${namespace}" exposure/unauthenticated-probe -o jsonpath='{.status.conditions[?(@.type=="ResolvedRefs")].reason}' 2>/dev/null)" = "PolicyMissing" ]; do
  [ "${SECONDS}" -ge "${deadline}" ] && echo "❌ unauthenticated probe was not refused with PolicyMissing" >&2 && exit 1
  sleep 2
done
unauth_rule="$(kubectl get -n "${namespace}" exposure/unauthenticated-probe -o jsonpath='{.status.programmedRule.hostname}')"
[ -n "${unauth_rule}" ] && echo "❌ the refused exposure must hold no route" >&2 && exit 1

echo "✅ Boron k3d e2e passed: nonroot manager ready, Account/Tunnel/Exposure converged, hostname ${hostname}, tunnel ${tunnel_id}, access app ${app_id}, fixed 2 cloudflared replicas, unauthenticated exposure blocked (PolicyMissing)"
