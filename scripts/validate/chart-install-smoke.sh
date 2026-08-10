#!/usr/bin/env bash
set -euo pipefail

# Install smoke for one chart, with a documented degradation.
#
# A real apiserver is the only thing that proves a chart INSTALLS rather than
# merely renders: admission, the kubeVersion floor, and Service wiring are all
# invisible to `helm template`. Where k3d, kubectl, and a live docker daemon are
# all present this delegates to scripts/ci/helm-smoke.sh, which brings up a
# throwaway cluster and installs both charts for real.
#
# Where they are not — a sandbox with no docker socket — this degrades to a
# server-free structural pass: render, then validate every rendered manifest with
# kubeconform. That is strictly weaker than an install and is labelled as such in
# the output, so a degraded run can never be mistaken for the real thing. CI's
# in-cluster job runs the undegraded path.
#
# Usage: chart-install-smoke.sh <primordial|garden>

target="${1:?usage: chart-install-smoke.sh <primordial|garden>}"

chart_primordial="infra/primordial_chart"
chart_garden="infra/garden_app_chart"

./scripts/local/chart-vendor.sh >/dev/null

if command -v k3d >/dev/null && command -v kubectl >/dev/null && docker info >/dev/null 2>&1; then
  echo "🚀 k3d + docker reachable — running the real install smoke for '${target}'"
  # helm-smoke.sh installs both charts into one throwaway cluster; a per-chart
  # cluster would double a five-minute rail for no extra evidence.
  ./scripts/ci/helm-smoke.sh
  echo "✅ ${target} install smoke green (real cluster)"
  exit 0
fi

echo "⚠️ DEGRADED: no reachable k3d/kubectl/docker — substituting render + kubeconform for the install."
echo "⚠️ This proves the manifests are structurally valid, NOT that they install. CI runs the real path."

command -v kubeconform >/dev/null || {
  echo "❌ neither a cluster nor kubeconform is available — no install evidence is obtainable" >&2
  exit 1
}

case "${target}" in
primordial)
  # The primordial chart emits operator CRs (Grafana*, LogtoApp,
  # PlatformDependency) whose schemas live in no public catalogue, so structural
  # validation here is necessarily missing-schema tolerant.
  helm template primordial-probe "${chart_primordial}" |
    kubeconform -strict -summary -ignore-missing-schemas
  ;;
garden)
  for profile in "${chart_garden}"/profiles/*.yaml; do
    name="$(basename "${profile}" .yaml)"
    [ "${name}" = "rejected-hosted-boron" ] && continue
    helm template "garden-${name}" "${chart_garden}" -f "${profile}" |
      kubeconform -strict -summary -ignore-missing-schemas
    echo "  ✅ ${name}"
  done
  ;;
*)
  echo "❌ unknown chart target '${target}'" >&2
  exit 1
  ;;
esac

echo "✅ ${target} install smoke green (DEGRADED: render + kubeconform)"
