#!/usr/bin/env bash
set -euo pipefail
CLUSTER="bunconsumer-$(head -c4 /dev/urandom | od -An -tx1 | tr -d ' \n')"
CTX="k3d-${CLUSTER}"
cleanup() {
  s=$?
  k3d cluster delete "${CLUSTER}" >/dev/null 2>&1 || true
  rm -rf infra/root_chart/files infra/primordial_chart/files/observability
  exit "$s"
}
trap cleanup EXIT

echo "=== k3d cluster create ${CLUSTER} ==="
k3d cluster create "${CLUSTER}" --servers 1 --agents 0 --image rancher/k3s:v1.31.5-k3s1 \
  --k3s-arg "--disable=traefik@server:*" --no-lb --wait

echo "=== apply test-only CRD fixtures ==="
kubectl --context "${CTX}" apply -f infra/primordial_chart/crds-local
kubectl --context "${CTX}" wait --for=condition=Established \
  crd/platformdependencies.fleet.atomi.cloud crd/logtoapps.fleet.atomi.cloud \
  crd/problems.atomi.cloud crd/externalsecrets.external-secrets.io \
  crd/grafanafolders.grafana.integreatly.org crd/grafanadashboards.grafana.integreatly.org \
  crd/grafanaalertrulegroups.grafana.integreatly.org --timeout=2m

echo "=== build-phase vendoring (both charts) ==="
mkdir -p infra/root_chart/files/config infra/primordial_chart/files
cp config/*.yaml infra/root_chart/files/config/ 2>/dev/null || printf 'app:\n  platform: diene\n  service: bunconsumer\n  module: worker\n' >infra/root_chart/files/config/settings.yaml
cp -r observability infra/primordial_chart/files/
# The committed export from the published @atomicloud/diene.problems is the real
# artifact; regenerate it only when absent so the smoke exercises the true shape.
[ -f infra/primordial_chart/files/problems.json ] || ./scripts/local/problems-export.sh --out infra/primordial_chart/files/problems.json
find infra/root_chart/files infra/primordial_chart/files -type f | head -20

echo "=== install APP chart ==="
# The real image is not published yet, so the smoke pins a public, pullable image
# and swaps the subcommands. This asserts INSTALL (every manifest admitted, the
# PreSync hook Job completes, the Deployment becomes Ready) — not app behavior.
helm --kube-context "${CTX}" upgrade --install bunconsumer infra/root_chart \
  --namespace diene --create-namespace \
  -f infra/root_chart/values.lapras.yaml \
  --set image.repository=busybox --set image.tag=1.37.0 \
  --set 'worker.args={sh,-c,while true; do sleep 5; done}' \
  --set 'dbInit.args={sh,-c,echo db-init ok}' \
  --set 'health.command={sh,-c,exit 0}' \
  --set podSecurityContext.runAsUser=0 --set podSecurityContext.runAsGroup=0 \
  --set podSecurityContext.runAsNonRoot=false --set podSecurityContext.fsGroup=null \
  --wait --timeout=3m

echo "=== install PRIMORDIAL chart (same cluster) ==="
helm --kube-context "${CTX}" upgrade --install bunconsumer-primordial infra/primordial_chart \
  --namespace diene \
  -f infra/primordial_chart/values.lapras.yaml \
  --set logtoApp.enabled=true --set logtoApp.type=MachineToMachine \
  --wait --timeout=3m

echo "=== EVIDENCE: helm list ==="
helm --kube-context "${CTX}" list -n diene
echo "=== EVIDENCE: app chart resources ==="
kubectl --context "${CTX}" -n diene get deployment,pod,configmap,job,externalsecret -l app.kubernetes.io/name=bunconsumer
echo "=== EVIDENCE: db-init hook Job completed ==="
kubectl --context "${CTX}" -n diene get job bunconsumer-dbinit -o jsonpath='{.status.succeeded} succeeded / {.status.failed} failed{"\n"}'
kubectl --context "${CTX}" -n diene logs job/bunconsumer-dbinit
echo "=== EVIDENCE: rolling update, not recreate ==="
kubectl --context "${CTX}" -n diene get deployment bunconsumer-worker -o jsonpath='strategy={.spec.strategy.type} probes: liveness={.spec.template.spec.containers[0].livenessProbe.exec.command} readiness={.spec.template.spec.containers[0].readinessProbe.exec.command}{"\n"}'
echo "=== EVIDENCE: primordial T3 CR set ==="
kubectl --context "${CTX}" -n diene get platformdependency,problem,logtoapp,grafanafolder,grafanadashboard,grafanaalertrulegroup
echo "=== EVIDENCE: PlatformDependency union spec ==="
kubectl --context "${CTX}" -n diene get platformdependency bunconsumer-lapras -o jsonpath='{.spec.landscape} db={.spec.database.type} kv={.spec.kv.type} cache={.spec.cache.type} store={.spec.store.type}{"\n"}'
echo "=== EVIDENCE: Problem row ==="
kubectl --context "${CTX}" -n diene get problem bunconsumer-lapras-v1 -o jsonpath='{.spec.platform}/{.spec.service}/{.spec.landscape}/{.spec.version} ids={.spec.problems[*].id}{"\n"}'
echo "=== EVIDENCE: Grafana folder uid ==="
kubectl --context "${CTX}" -n diene get grafanafolder bunconsumer-obsfolder -o jsonpath='uid={.spec.uid} parent={.spec.parentFolderUID}{"\n"}'
echo "=== EVIDENCE: zero dashboards / zero alerts render cleanly (Gate 4/5 = none) ==="
kubectl --context "${CTX}" -n diene get grafanadashboard,grafanaalertrulegroup 2>&1 | tail -2
echo "✅ two-chart install smoke complete"
