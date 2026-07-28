#!/usr/bin/env bash
set -euo pipefail

# The primordial chart install smoke (R20). `helm lint` and `helm template` prove
# the chart PARSES; only an install proves the API server ACCEPTS what it renders.
#
# THIS SCRIPT CREATES AND DESTROYS ITS OWN CLUSTER, AND NEVER INSTALLS INTO A
# CONTEXT IT DID NOT CREATE.
#
# That is not a precaution. There is no local verification cluster on a
# developer box here, and `kubectl` answers anyway: measured on this machine,
# `kubectl config current-context` was `pichu-ruby` at one point and `entei-opal`
# an hour later — the second a DigitalOcean managed cluster. Both are remote,
# shared AtomiCloud infrastructure. A `helm install` with no guard does not fail
# and prints no warning; it simply succeeds, against production-adjacent
# infrastructure. The context also CHANGED under us mid-task, which is why the
# assertion below sits immediately before the install rather than once at the top.

root_dir="$(git rev-parse --show-toplevel)"
cd "${root_dir}"

command -v k3d >/dev/null 2>&1 || {
  echo "❌ 'k3d' is not on PATH: the install smoke cannot create its own cluster" >&2
  exit 1
}

cluster="flutterbase-$(head -c6 /dev/urandom | od -An -tx1 | tr -d ' \n')"
context="k3d-${cluster}"

# Destroy the cluster on EVERY exit path, including failure, and put the caller's
# kubectl context back where it was.
previous_context="$(kubectl config current-context 2>/dev/null || echo '')"
cleanup() {
  status=$?
  trap - EXIT
  echo "🧹 deleting cluster ${cluster}"
  k3d cluster delete "${cluster}" >/dev/null 2>&1 || true
  rm -rf -- "${root_dir}/infra/primordial_chart/files"
  [ -n "${previous_context}" ] && kubectl config use-context "${previous_context}" >/dev/null 2>&1 || true
  exit "${status}"
}
trap cleanup EXIT INT TERM

echo "📝 context before this smoke: ${previous_context:-<none>}"

echo "🔨 k3d cluster create ${cluster}..."
k3d cluster create "${cluster}" --servers 1 --agents 0 --image rancher/k3s:v1.31.5-k3s1 \
  --k3s-arg "--disable=traefik@server:*" --no-lb --wait

echo "🔨 applying test-only CRD fixtures..."
crd_count="$(find infra/primordial_chart/crds-local -name '*.yaml' -type f | wc -l | tr -d ' ')"
echo "📝 ${crd_count} local CRD fixture files"
[ "${crd_count}" -eq 0 ] && echo "❌ no local CRD fixtures found" >&2 && exit 1
kubectl --context "${context}" apply -f infra/primordial_chart/crds-local
kubectl --context "${context}" wait --for=condition=Established --all crd --timeout=2m
established="$(kubectl --context "${context}" get crd -o name | wc -l | tr -d ' ')"
echo "📝 ${established} CRDs registered"
[ "${established}" -eq 0 ] && echo "❌ no CRDs registered" >&2 && exit 1

# The build-phase copy the dashboard/alert templates glob over. Helm cannot read
# outside the chart directory, so the root `observability/` is copied in here and
# never committed. Absent today: this node's dashboard/alert content is owed.
echo "🔨 build-phase observability vendoring..."
mkdir -p infra/primordial_chart/files
[ -d observability ] && cp -r observability infra/primordial_chart/files/
echo "📝 vendored observability files: $(find infra/primordial_chart/files -type f 2>/dev/null | wc -l | tr -d ' ')"

# ############################################################################
# THE CLUSTER GUARD. Immediately before the install — not once at the start,
# because a context can change under you. Abort rather than install into a
# context this script did not create.
# ############################################################################
kubectl config use-context "${context}" >/dev/null
active="$(kubectl config current-context)"
echo "📝 active context immediately before helm install: ${active}"
echo "📝 expected context (created by this script): ${context}"
[ "${active}" != "${context}" ] && echo "❌ REFUSING TO INSTALL: active context '${active}' is not the cluster this script created ('${context}')" >&2 && exit 1
# k3d names every context it creates `k3d-<cluster>`; a context lacking that
# prefix cannot be one of ours, whatever it is called.
case "${active}" in
k3d-*) : ;;
*)
  echo "❌ REFUSING TO INSTALL: context '${active}' is not a k3d context" >&2
  exit 1
  ;;
esac
echo "✅ cluster guard passed: installing into a k3d cluster created by this run"

echo "🔨 installing the primordial chart..."
helm --kube-context "${context}" upgrade --install flutterbase-primordial infra/primordial_chart \
  --namespace platform --create-namespace \
  --wait --timeout=5m

echo "📝 deployed releases:"
helm --kube-context "${context}" list --namespace platform
releases="$(helm --kube-context "${context}" list --namespace platform --deployed -o json | jq 'length')"
echo "📝 ${releases} deployed release(s)"
[ "${releases}" -lt 1 ] && echo "❌ the chart did not produce a deployed release" >&2 && exit 1

# Assert the API server ADMITTED the custom resources, not merely that helm
# reported success. A release can be deployed with nothing accepted.
echo "📝 admitted custom resources:"
kubectl --context "${context}" --namespace platform get logtoapp,grafanafolder -o name
admitted="$(kubectl --context "${context}" --namespace platform get logtoapp,grafanafolder -o name | wc -l | tr -d ' ')"
echo "📝 ${admitted} custom resource(s) admitted"
[ "${admitted}" -lt 2 ] && echo "❌ expected the LogtoApp and the GrafanaFolder to be admitted, found ${admitted}" >&2 && exit 1

# The callback list is what makes the LogtoApp useful; prove it survived the
# round trip through the API server rather than trusting the render.
callbacks="$(kubectl --context "${context}" --namespace platform get logtoapp service-app -o jsonpath='{.spec.extraRedirectUris[*]}' | wc -w | tr -d ' ')"
echo "📝 LogtoApp callbacks stored in the cluster: ${callbacks}"
[ "${callbacks}" -lt 1 ] && echo "❌ the admitted LogtoApp carries no redirect URI" >&2 && exit 1

echo "✅ primordial chart installed into k3d cluster ${cluster} with ${admitted} resources admitted"
