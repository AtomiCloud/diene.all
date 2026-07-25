#!/usr/bin/env bash
set -euo pipefail

# Helm rail: everything that must hold for the two charts before they can ship.
#
# The Garden app chart's `values.schema.json` is the load-bearing gate — it is
# what makes a hosted-Boron or public-callback exposure *unrepresentable* rather
# than merely discouraged. A gate is only real if something red-lights when it
# is removed, so this rail asserts the negative fixture FAILS just as hard as it
# asserts the seven profiles pass.
#
# k3d install smoke runs only where a cluster tool is actually present. Every
# other stage is mandatory: a missing helm here is a broken CI image, not a skip.

chart_primordial="infra/primordial_chart"
chart_garden="infra/garden_app_chart"
rejection_fixture="${chart_garden}/profiles/rejected-hosted-boron.yaml"

command -v helm >/dev/null || {
  echo "❌ helm is missing from the CI shell — see nix/env.nix" >&2
  exit 1
}

echo "📦 Vendoring observability/ into the primordial chart..."
./scripts/local/chart-vendor.sh

echo "🧹 Linting both charts..."
helm lint "${chart_primordial}" "${chart_garden}"

echo "🧪 Templating the primordial chart..."
helm template primordial-ci "${chart_primordial}" >/dev/null

echo "🧪 Templating every Garden profile..."
for profile in "${chart_garden}"/profiles/*.yaml; do
  name="$(basename "${profile}" .yaml)"
  [ "${name}" = "$(basename "${rejection_fixture}" .yaml)" ] && continue
  helm template "garden-${name}" "${chart_garden}" -f "${profile}" >/dev/null
  echo "  ✅ ${name}"
done

# The gate proves itself here. If the schema ever stops rejecting a hosted-Boron
# declaration this exits 0 and the rail goes red — which is the point.
echo "🧪 Asserting the hosted-Boron fixture is REJECTED..."
if helm template garden-rejected "${chart_garden}" -f "${rejection_fixture}" >/dev/null 2>&1; then
  echo "❌ hosted-Boron values rendered successfully — the schema gate is not holding" >&2
  exit 1
fi
echo "  ✅ rejected as required"

echo "🛡️ Checking chart ownership..."
./scripts/validate/chart-ownership.sh

if command -v kubeconform >/dev/null; then
  echo "🧾 Validating rendered manifests with kubeconform..."
  for profile in "${chart_garden}"/profiles/*.yaml; do
    name="$(basename "${profile}" .yaml)"
    [ "${name}" = "$(basename "${rejection_fixture}" .yaml)" ] && continue
    helm template "garden-${name}" "${chart_garden}" -f "${profile}" |
      kubeconform -strict -summary -ignore-missing-schemas
  done
  # The primordial chart renders operator CRs (Grafana*, LogtoApp,
  # PlatformDependency) whose schemas live in no public catalogue, so structural
  # validation there is necessarily missing-schema tolerant.
  helm template primordial-ci "${chart_primordial}" |
    kubeconform -strict -summary -ignore-missing-schemas
else
  echo "⏭️ kubeconform absent — skipping manifest schema validation"
fi

# k3d and kubectl ship with infrautils, so their presence proves nothing about
# the runner — a reachable docker daemon is the real discriminator. HELM_SMOKE
# overrides the probe in both directions: `1` makes a missing daemon a hard
# failure (for a runner that is supposed to have one), `0` skips outright.
smoke="${HELM_SMOKE:-auto}"
if [ "${smoke}" = "0" ]; then
  echo "⏭️ HELM_SMOKE=0 — skipping the cluster install smoke"
elif command -v k3d >/dev/null && command -v kubectl >/dev/null && docker info >/dev/null 2>&1; then
  echo "🚀 docker daemon reachable — running the install smoke..."
  ./scripts/ci/helm-smoke.sh
elif [ "${smoke}" = "1" ]; then
  echo "❌ HELM_SMOKE=1 but no reachable k3d/kubectl/docker runner" >&2
  exit 1
else
  echo "⏭️ no reachable docker daemon — skipping the cluster install smoke"
fi

echo "✅ Helm rail green"
