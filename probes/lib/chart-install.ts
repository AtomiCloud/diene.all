// Local k3d install harness shared by the two chart-install smokes.
//
// The install runs SELF-CONTAINED inside the probe surface: the go-consumer
// branch ships no `scripts/validate/chart-install.sh`, and `scripts/` is another
// worker's file. Everything here therefore stays inside `probes/`.
//
// UNIQUE PER-INVOCATION NAME (PROBES §5 addendum, binding): a fixed k3d cluster
// name collides under parallelism and cascades a healthy-control failure into a
// whole-suite fold (one fixed name folded 140/141 rows on operator-template). The
// cluster name is derived per invocation from `/dev/urandom`, and every
// kubectl/helm call is pinned to that cluster's own context so nothing can leak
// into a neighbouring cluster or the caller's current kube context.
//
// The two smokes deliberately share ONE sequence: both charts must install into
// the SAME cluster (the goal's DoD says "both install into one local cluster"),
// and each row asserts its own release plus its own rendered evidence. The rows
// stay independently invoked mechanisms — each brings up its own cluster and each
// fails on its own evidence.
import { expectScriptGreen } from './sandbox-script';

// The real image is not published, so the install pins a public, pullable image
// and swaps the subcommands. This asserts INSTALL — every manifest admitted, the
// PreSync hook Job completing, the Deployment reaching Ready — not app behavior.
// The security context is relaxed for busybox alone; the chart's own unprivileged
// defaults are proven by the render rows and the image-policy gates.
export const CHART_INSTALL_SCRIPT = `CLUSTER="goconsumer-$(head -c6 /dev/urandom | od -An -tx1 | tr -d ' \\n')"
CTX="k3d-\${CLUSTER}"
echo "cluster \${CLUSTER}"
cleanup() {
  status=$?
  k3d cluster delete "\${CLUSTER}" >/dev/null 2>&1 || true
  rm -rf infra/root_chart/files infra/primordial_chart/files/observability
  exit "\${status}"
}
trap cleanup EXIT

echo "=== k3d cluster create \${CLUSTER} ==="
# The k3s image is PINNED deliberately. Without --image, k3d falls back to a
# default that has been v1.21.7+k3s1 here, and both charts declare
# kubeVersion '>=1.27.0-0', so every install row fails with
# "chart requires kubeVersion ... incompatible with Kubernetes v1.21.7+k3s1" —
# a venue defect that reads exactly like a chart defect. The reference
# bun-consumer pins the same image in scripts/validate/chart-install.sh.
k3d cluster create "\${CLUSTER}" --servers 1 --agents 0 --image rancher/k3s:v1.31.5-k3s1 \\
  --k3s-arg "--disable=traefik@server:*" --no-lb --wait
# CONTEXT FENCE (briana/harriett, 2026-07-28T09:5xZ). The AMBIENT kube context on
# this box is \`entei-opal\`, a REMOTE DigitalOcean cluster — verified with
# \`kubectl config current-context\`. Every other call below is pinned with
# --context/--kube-context, but this version probe was NOT, so it reported the
# REMOTE server's version instead of the k3d cluster we just created. The comment
# above explains why that matters: a wrong kubeVersion here is "a venue defect
# that reads exactly like a chart defect".
#
# Assert the context resolves to the cluster THIS run created, and abort if not.
# Never install against a context we did not create.
if ! kubectl config get-contexts -o name 2>/dev/null | grep -Fxq "\${CTX}"; then
  echo "❌ context \${CTX} does not exist — refusing to touch any cluster" >&2
  exit 1
fi
echo "=== k3s server version (must satisfy the charts' kubeVersion) ==="
kubectl --context "\${CTX}" version -o json 2>/dev/null | jq -r '.serverVersion.gitVersion' \\
  || kubectl --context "\${CTX}" version --short 2>/dev/null | rg Server

echo "=== apply test-only CRD fixtures ==="
crds="$(find infra/primordial_chart/crds-local -name '*.yaml' | sort)"
crd_count="$(printf '%s\\n' "\${crds}" | grep -c . || true)"
echo "\${crd_count} local CRD fixture files"
[ "\${crd_count}" -eq 0 ] && { echo "❌ no local CRD fixtures found — refusing an empty install" >&2; exit 1; }
kubectl --context "\${CTX}" apply -f infra/primordial_chart/crds-local
established="$(kubectl --context "\${CTX}" get crd -o name | wc -l | tr -d ' ')"
echo "\${established} CRDs registered"
[ "\${established}" -eq 0 ] && { echo "❌ no CRDs registered" >&2; exit 1; }
kubectl --context "\${CTX}" wait --for=condition=Established --all crd --timeout=2m

echo "=== build-phase vendoring (B30.3) ==="
mkdir -p infra/root_chart/files/config infra/primordial_chart/files
cp config/settings.yaml config/*.settings.yaml infra/root_chart/files/config/
[ -d observability ] && cp -r observability infra/primordial_chart/files/
vendored="$(find infra/root_chart/files infra/primordial_chart/files -type f | wc -l | tr -d ' ')"
echo "\${vendored} vendored chart files"
[ "\${vendored}" -eq 0 ] && { echo "❌ chart vendoring produced no files" >&2; exit 1; }

echo "=== install APP chart ==="
helm --kube-context "\${CTX}" upgrade --install go-consumer infra/root_chart \\
  --namespace diene --create-namespace \\
  --values infra/root_chart/values.lapras.yaml \\
  --set image.repository=busybox --set image.tag=1.37.0 \\
  --set 'worker.args={sh,-c,while true; do sleep 5; done}' \\
  --set 'dbInit.args={sh,-c,echo db-init ok}' \\
  --set 'health.command={sh,-c,exit 0}' \\
  --set podSecurityContext.runAsUser=0 --set podSecurityContext.runAsGroup=0 \\
  --set podSecurityContext.runAsNonRoot=false --set podSecurityContext.fsGroup=null \\
  --set containerSecurityContext.readOnlyRootFilesystem=false \\
  --wait --timeout=5m

echo "=== install PRIMORDIAL chart (same cluster) ==="
helm --kube-context "\${CTX}" upgrade --install go-consumer-primordial infra/primordial_chart \\
  --namespace diene \\
  --values infra/primordial_chart/values.lapras.yaml \\
  --wait --timeout=5m

echo "=== EVIDENCE: helm list ==="
helm --kube-context "\${CTX}" list --namespace diene
releases="$(helm --kube-context "\${CTX}" list --namespace diene --deployed -o json | jq 'length')"
echo "\${releases} deployed releases"
[ "\${releases}" -lt 2 ] && { echo "❌ expected 2 deployed releases, found \${releases}" >&2; exit 1; }

echo "=== EVIDENCE: app chart workloads ==="
kubectl --context "\${CTX}" --namespace diene get deployment,job,configmap,externalsecret -o name
ready="$(kubectl --context "\${CTX}" --namespace diene get deployment goconsumer-worker \\
  -o jsonpath='{.status.readyReplicas}')"
echo "worker readyReplicas \${ready:-0}"
[ "\${ready:-0}" -lt 1 ] && { echo "❌ worker Deployment never became Ready" >&2; exit 1; }
hook="$(kubectl --context "\${CTX}" --namespace diene get job goconsumer-dbinit \\
  -o jsonpath='{.status.succeeded}')"
echo "db-init hook Job succeeded \${hook:-0}"
[ "\${hook:-0}" -lt 1 ] && { echo "❌ db-init pre-sync hook Job never completed" >&2; exit 1; }

echo "=== EVIDENCE: primordial T3 CR set ==="
kubectl --context "\${CTX}" --namespace diene get platformdependency,problem -o name
crs="$(kubectl --context "\${CTX}" --namespace diene get platformdependency,problem -o name | wc -l | tr -d ' ')"
echo "\${crs} T3 custom resources admitted"
[ "\${crs}" -eq 0 ] && { echo "❌ no T3 custom resources were admitted" >&2; exit 1; }
echo "✅ both charts installed into cluster \${CLUSTER}"
`;

export async function runChartInstall(repo: any, label: string, markers: string[]): Promise<void> {
  await expectScriptGreen(repo, CHART_INSTALL_SCRIPT, label, markers, { timeoutMs: 1800000 });
}
