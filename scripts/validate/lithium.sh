#!/usr/bin/env bash
set -euo pipefail

mode="${1:-all}"
tmp="$(mktemp -d)"
trap 'rm -rf "${tmp}"' EXIT
fleet_render() { helm template lithium chart --namespace diene "$@"; }
primordial_render() { helm template lithium-primordial primordial-chart --namespace diene "$@"; }

case "${mode}" in
all | lint | fleet | garden | negative | labels | rendered-manifests | publish) ;;
*)
  echo "❌ unknown Lithium validation mode ${mode}" >&2
  exit 1
  ;;
esac

if [ "${mode}" = all ] || [ "${mode}" = lint ]; then
  helm lint chart
  helm lint primordial-chart
fi

if [ "${mode}" = all ] || [ "${mode}" = fleet ]; then
  fleet_render >"${tmp}/fleet.yaml"
  primordial_render >"${tmp}/primordial.yaml"
  rg -q 'type: LoadBalancer' "${tmp}/fleet.yaml"
  rg -q 'https://api.lithium.diene.mew.cluster.atomi.cloud' "${tmp}/fleet.yaml"
  rg -q 'key: "/diene/lithium"' "${tmp}/fleet.yaml"
  [ "$(rg -c '^kind: ExternalSecret$' "${tmp}/fleet.yaml")" = 2 ]
  [ "$(rg -c '^kind: PlatformDependency$' "${tmp}/primordial.yaml")" = 1 ]
  [ "$(rg -c '^kind: VirtualLandscapeService$' "${tmp}/primordial.yaml")" = 1 ]
  if rg -q 'privatePath:' chart primordial-chart; then
    echo "❌ Lithium must not expose a private path" >&2
    exit 1
  fi
fi

if [ "${mode}" = all ] || [ "${mode}" = garden ]; then
  for profile in lapras ditto rotom absol eevee plusle minun; do
    helm template lithium chart --namespace diene --values "chart/values.${profile}.yaml" >"${tmp}/${profile}.yaml"
    rg -q "api.lithium.diene.${profile}-001.${profile}" "${tmp}/${profile}.yaml"
    rg -q "name: lithium-${profile}-db" "${tmp}/${profile}.yaml"
    rg -q "name: lithium-${profile}-boot" "${tmp}/${profile}.yaml"
    [ "$(rg -c '^kind: Service$' "${tmp}/${profile}.yaml")" = 2 ]
    if rg -q 'kind: ExternalSecret|kind: PlatformDependency|kind: VirtualLandscapeService|type: LoadBalancer|kind: HTTPRoute|kind: Certificate|kind: Gateway' "${tmp}/${profile}.yaml"; then
      echo "❌ ${profile} rendered a fleet or edge-owned object" >&2
      exit 1
    fi
    rg -q 'atomi.cloud/instance-uid:' "${tmp}/${profile}.yaml"
    rg -q 'atomi.cloud/allocation-generation:' "${tmp}/${profile}.yaml"
  done
  helm template lithium-primordial primordial-chart --namespace diene --values primordial-chart/values.lapras.yaml >"${tmp}/local-primordial.yaml"
  if rg -q '^kind:' "${tmp}/local-primordial.yaml"; then
    echo "❌ Garden-local primordial render was not empty" >&2
    exit 1
  fi
fi

if [ "${mode}" = all ] || [ "${mode}" = negative ]; then
  if primordial_render --set-json 'platformDependencies=[{"vlandscape":"mew","placement":{"preferredHost":"raichu"},"deletionPolicy":{"retainSecret":"168h"}},{"vlandscape":"mew","placement":{"preferredHost":"amphoros"},"deletionPolicy":{"retainSecret":"168h"}}]' >/dev/null 2>"${tmp}/dup.err"; then
    echo "❌ duplicate dependency writer was accepted" >&2
    exit 1
  fi
  rg -q 'Conflict: duplicate PlatformDependency writer' "${tmp}/dup.err"
  if helm template lithium chart --set distributionMode=INVALID >/dev/null 2>"${tmp}/mode.err"; then
    echo "❌ invalid distribution mode was accepted" >&2
    exit 1
  fi
  rg -q "(distributionMode must be FLEET or GARDEN-LOCAL|value must be one of 'FLEET', 'GARDEN-LOCAL')" "${tmp}/mode.err"
  if helm template lithium chart --values chart/values.lapras.yaml --set garden.bootSecret= >/dev/null 2>"${tmp}/blank.err"; then
    echo "❌ blank boot secret source was accepted" >&2
    exit 1
  fi
  rg -q 'garden.bootSecret is required' "${tmp}/blank.err"
  fleet_render >"${tmp}/gate.yaml"
  rg -q 'test -n.*DB_URL.*test -n.*SEED_M2M_CLIENT_ID.*test -n.*SEED_M2M_CLIENT_SECRET' "${tmp}/gate.yaml"
fi

if [ "${mode}" = all ] || [ "${mode}" = labels ]; then
  fleet_render --set labelPrefix=example.dev >"${tmp}/labels.yaml"
  rg -q 'example.dev/service: "lithium"' "${tmp}/labels.yaml"
  if rg -q 'atomi.cloud/service:' "${tmp}/labels.yaml"; then
    echo "❌ default label prefix survived an override" >&2
    exit 1
  fi
fi

if [ "${mode}" = all ] || [ "${mode}" = rendered-manifests ]; then
  fleet_render >"${tmp}/fleet.yaml"
  primordial_render >"${tmp}/primordial.yaml"
  kubeconform -strict -ignore-missing-schemas -summary \
    -schema-location 'schemas/{{ .ResourceKind }}.json' \
    "${tmp}/fleet.yaml" "${tmp}/primordial.yaml"
fi

if [ "${mode}" = all ] || [ "${mode}" = publish ]; then
  PUBLISH_MODE=git PUBLISH_DRY_RUN=true RELEASE_VERSION=v0.1.0 PUBLISH_OUTPUT_DIR="${tmp}/git" bash scripts/ci/publish.sh >/dev/null
  PUBLISH_MODE=oci PUBLISH_DRY_RUN=true RELEASE_VERSION=v0.1.0 PUBLISH_OUTPUT_DIR="${tmp}/oci" bash scripts/ci/publish.sh >/dev/null
  test -s "${tmp}/oci/diene-lithium-0.1.0.tgz"
  test -s "${tmp}/oci/diene-lithium-primordial-0.1.0.tgz"
  [ "$(yq -r '.appVersion' chart/Chart.yaml)" = "$(yq -r '.image.tag' chart/values.yaml)" ]
fi

echo "✅ Lithium ${mode} validation passed"
