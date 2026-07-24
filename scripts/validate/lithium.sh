#!/usr/bin/env bash
set -euo pipefail

mode="${1:-all}"
tmp="$(mktemp -d)"
filter_container=""
filter_upstream=""
cleanup() {
  if [ -n "${filter_upstream}" ]; then
    docker rm -f "${filter_upstream}" >/dev/null 2>&1 || true
  fi
  if [ -n "${filter_container}" ]; then
    docker rm -f "${filter_container}" >/dev/null 2>&1 || true
  fi
  rm -rf "${tmp}"
}
trap cleanup EXIT
fleet_render() { helm template lithium chart --namespace diene "$@"; }
primordial_render() { helm template lithium-primordial primordial-chart --namespace diene "$@"; }

case "${mode}" in
all | lint | fleet | garden | filter-runtime | negative | labels | rendered-manifests | publish) ;;
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
  rg -q 'key: "/diene/lithium/SEED_M2M_CLIENT_ID"' "${tmp}/fleet.yaml"
  rg -q 'key: "/diene/lithium/SEED_M2M_CLIENT_SECRET"' "${tmp}/fleet.yaml"
  rg -q 'key: "/database/lithium/DB_URL"' "${tmp}/fleet.yaml"
  rg -q 'name: carbon-store' "${tmp}/fleet.yaml"
  if rg -q 'name: lithium-store' "${tmp}/fleet.yaml"; then
    echo "❌ Fleet must consume the platform-owned carbon-store, not a chart-local store" >&2
    exit 1
  fi
  fleet_render --set serviceTree.platform=raichu >"${tmp}/fleet-raichu.yaml"
  rg -q 'key: "/raichu/lithium/SEED_M2M_CLIENT_ID"' "${tmp}/fleet-raichu.yaml"
  rg -q 'key: "/raichu/lithium/SEED_M2M_CLIENT_SECRET"' "${tmp}/fleet-raichu.yaml"
  if rg -q 'key: "/diene/lithium/' "${tmp}/fleet-raichu.yaml"; then
    echo "❌ fleet boot path did not follow platform identity" >&2
    exit 1
  fi
  rg -q 'key: "/database/lithium/DB_URL"' "${tmp}/fleet-raichu.yaml"
  if rg -q 'key: "/lithium/database"|property:' "${tmp}/fleet.yaml" "${tmp}/fleet-raichu.yaml"; then
    echo "❌ Fleet database path must be the C0 /database/lithium folder" >&2
    exit 1
  fi
  [ "$(rg -c '^kind: ExternalSecret$' "${tmp}/fleet.yaml")" = 2 ]
  if rg -q '^kind: SecretStore$' "${tmp}/fleet.yaml"; then
    echo "❌ Lithium must not render a chart-local SecretStore" >&2
    exit 1
  fi
  [ "$(rg -c '^kind: Service$' "${tmp}/fleet.yaml")" = 1 ]
  rg -q 'targetPort: management' "${tmp}/fleet.yaml"
  if rg -q 'lithium-management|lithium-public-filter|kind: NetworkPolicy|name: public-filter' "${tmp}/fleet.yaml"; then
    echo "❌ FLEET must expose raw OIDC and /api through one LB Service" >&2
    exit 1
  fi
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
    rg -q "atomi.cloud/landscape: \"${profile}\"" "${tmp}/${profile}.yaml"
    rg -q "name: lithium-${profile}-db" "${tmp}/${profile}.yaml"
    rg -q "name: lithium-${profile}-boot" "${tmp}/${profile}.yaml"
    [ "$(rg -c '^kind: Service$' "${tmp}/${profile}.yaml")" = 2 ]
    [ "$(rg -c '^kind: Deployment$' "${tmp}/${profile}.yaml")" = 1 ]
    rg -q 'name: lithium-public' "${tmp}/${profile}.yaml"
    rg -q 'name: lithium-management' "${tmp}/${profile}.yaml"
    rg -q 'targetPort: public' "${tmp}/${profile}.yaml"
    rg -q 'targetPort: management' "${tmp}/${profile}.yaml"
    rg -q 'atomi.cloud/public-filter-version: v1' "${tmp}/${profile}.yaml"
    rg -q '^kind: NetworkPolicy$' "${tmp}/${profile}.yaml"
    rg -q 'name: lithium-management-isolation' "${tmp}/${profile}.yaml"
    if rg -q 'kind: ExternalSecret|kind: PlatformDependency|kind: VirtualLandscapeService|type: LoadBalancer|kind: HTTPRoute|kind: Certificate|kind: Gateway' "${tmp}/${profile}.yaml"; then
      echo "❌ ${profile} rendered a fleet or edge-owned object" >&2
      exit 1
    fi
    rg -q 'atomi.cloud/instance-uid:' "${tmp}/${profile}.yaml"
    rg -q 'atomi.cloud/allocation-generation:' "${tmp}/${profile}.yaml"
  done
  rg -q 'https://api.lithium.diene.lapras-001.lapras.admin.atomi.cloud' "${tmp}/lapras.yaml"
  rg -q 'http://api.lithium.diene.ditto-001.ditto.localhost:18081' "${tmp}/ditto.yaml"
  rg -q 'http://api.lithium.diene.rotom-001.rotom.localhost:18082' "${tmp}/rotom.yaml"
  rg -q 'http://api.lithium.diene.absol-001.absol.localhost:18083' "${tmp}/absol.yaml"
  for profile in eevee plusle minun; do
    rg -q "https://api.lithium.diene.${profile}-001.${profile}.dev.atomi.cloud" "${tmp}/${profile}.yaml"
  done
  rg -Fq 'location = /healthz { return 200; }' "${tmp}/lapras.yaml"
  rg -Fq 'oidc/(?:\.well-known/openid-configuration|jwks|auth|token' "${tmp}/lapras.yaml"
  rg -Fq 'api/experience(?:/|$)' "${tmp}/lapras.yaml"
  rg -Fq 'sign-in|register|single-sign-on|consent|device' "${tmp}/lapras.yaml"
  rg -Fq 'assets/' "${tmp}/lapras.yaml"
  rg -Fq 'location / { return 404; }' "${tmp}/lapras.yaml"
  if rg -F 'location ~ ^/api/' "${tmp}/lapras.yaml" | rg -Fv 'location ~ ^/api/experience' >/dev/null; then
    echo "❌ Garden public filter widened to all /api routes" >&2
    exit 1
  fi
  rg -q 'name: lithium-lapras-db' "${tmp}/lapras.yaml"
  if rg -q 'name: lithium-lapras-db' "${tmp}/ditto.yaml"; then
    echo "❌ concurrent Garden instances shared a database Secret reference" >&2
    exit 1
  fi
  helm template lithium-primordial primordial-chart --namespace diene --values primordial-chart/values.lapras.yaml >"${tmp}/local-primordial.yaml"
  if rg -q '^kind:' "${tmp}/local-primordial.yaml"; then
    echo "❌ Garden-local primordial render was not empty" >&2
    exit 1
  fi
fi

if [ "${mode}" = filter-runtime ]; then
  helm template lithium chart --namespace diene --values chart/values.lapras.yaml >"${tmp}/lapras.yaml"
  mkdir -p "${tmp}/public-filter"
  yq -r 'select(.kind == "ConfigMap" and .metadata.name == "lithium-public-filter") | .data."default.conf"' "${tmp}/lapras.yaml" >"${tmp}/public-filter/default.conf"
  filter_container="lithium-public-filter-$RANDOM-$$"
  docker run -d --rm --name "${filter_container}" --read-only --tmpfs /tmp:uid=101,gid=101 \
    -v "${tmp}/public-filter/default.conf:/etc/nginx/conf.d/default.conf:ro" \
    -p 127.0.0.1::8080 \
    nginxinc/nginx-unprivileged@sha256:65e3e85dbaed8ba248841d9d58a899b6197106c23cb0ff1a132b7bfe0547e4c0 >/dev/null
  filter_upstream="lithium-public-filter-upstream-$RANDOM-$$"
  docker run -d --rm --name "${filter_upstream}" --network "container:${filter_container}" busybox:1.36.1 \
    sh -ec 'mkdir -p /www/oidc/.well-known /www/sign-in/assets /www/api/experience; for path in /oidc/.well-known/openid-configuration /oidc/jwks /sign-in/assets/index.js /api/experience/interaction; do printf allowed >"/www${path}"; done; exec httpd -f -p 3001 -h /www' >/dev/null
  filter_port="$(docker port "${filter_container}" 8080/tcp | awk -F: '{print $NF}')"
  filter_status() {
    curl --retry 10 --retry-connrefused --silent --show-error --output /dev/null --write-out '%{http_code}' "http://127.0.0.1:${filter_port}$1"
  }
  [ "$(filter_status /healthz)" = 200 ]
  # The private upstream returns 200 only for these v1.41 fixtures, proving that
  # discovery, JWKS, Experience, and the sign-in SPA asset traverse the filter.
  [ "$(filter_status /oidc/.well-known/openid-configuration)" = 200 ]
  [ "$(filter_status /oidc/jwks)" = 200 ]
  [ "$(filter_status /api/experience/interaction)" = 200 ]
  [ "$(filter_status /sign-in/assets/index.js)" = 200 ]
  [ "$(filter_status /api/applications)" = 404 ]
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
  rg -q 'image: "busybox:1.36.1"' "${tmp}/gate.yaml"
  rg -q 'runAsUser: 10001' "${tmp}/gate.yaml"
  rg -q 'runAsNonRoot: true, runAsUser: 10001, runAsGroup: 10001' "${tmp}/gate.yaml"
  rg -Fq 'command: ["npm", "run", "cli", "db", "seed", "--", "--swe", "--dapc"]' "${tmp}/gate.yaml"
  yq -e 'select(.kind == "Deployment") | .spec.template.spec.initContainers[] | select(.name == "database-bootstrap") | select((.env | length) == 1) | select(.env[0].name == "DB_URL")' "${tmp}/gate.yaml" >/dev/null
  yq -e 'select(.kind == "Deployment") | .spec.template.spec.initContainers[] | select(.name == "database-bootstrap") | .volumeMounts[] | select(.mountPath == "/etc/logto/packages/cli/alteration-scripts")' "${tmp}/gate.yaml" >/dev/null
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
  if ! rg -q 'serve: true' "${tmp}/primordial.yaml"; then
    echo "❌ VLS fragment must emit its authoritative serve: true field" >&2
    exit 1
  fi
  if yq -e 'select(.kind == "VirtualLandscapeService" and .spec.serve != true)' "${tmp}/primordial.yaml" >/dev/null 2>&1; then
    echo "❌ every VLS fragment must set spec.serve: true" >&2
    exit 1
  fi
fi

if [ "${mode}" = all ] || [ "${mode}" = publish ]; then
  PUBLISH_MODE=git PUBLISH_DRY_RUN=true RELEASE_VERSION=v1.41.0 PUBLISH_OUTPUT_DIR="${tmp}/git" bash scripts/ci/publish.sh >/dev/null
  PUBLISH_MODE=oci PUBLISH_DRY_RUN=true RELEASE_VERSION=v1.41.0 PUBLISH_OUTPUT_DIR="${tmp}/oci" bash scripts/ci/publish.sh >/dev/null
  test -s "${tmp}/oci/diene-lithium-1.41.0.tgz"
  test -s "${tmp}/oci/diene-lithium-primordial-1.41.0.tgz"
  [ "$(yq -r '.appVersion' chart/Chart.yaml)" = "$(yq -r '.image.tag' chart/values.yaml)" ]
fi

echo "✅ Lithium ${mode} validation passed"
