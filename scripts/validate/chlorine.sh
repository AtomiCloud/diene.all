#!/usr/bin/env bash
# Chlorine unit-tier validation (materialized stakater/reloader engine wrapper —
# S30, no probe matrix). One mode per independently invoked mechanism; the CI
# orchestrator calls them in order. Positive assertion and its negative fixture
# live together in each mode.
set -euo pipefail

mode="${1:-}"
release="${RELEASE:-chlorine}"
namespace="${NAMESPACE:-reloader}"
landscape_overlay="chart/values.example.yaml"
cluster_overlay="chart/values.lapras.yaml"
tmp="$(mktemp -d)"
trap 'rm -rf "${tmp}"' EXIT

[ -z "${mode}" ] && echo "❌ validation mode not set" >&2 && exit 1

# The committed stacks rendered by the render/lint/manifest gates.
stacks_render() {
  local out_prefix="$1"
  helm template "${release}" chart --namespace "${namespace}" >"${out_prefix}-base.yaml"
  helm template "${release}" chart --namespace "${namespace}" \
    --values "${landscape_overlay}" --values "${cluster_overlay}" >"${out_prefix}-stack.yaml"
}

case "${mode}" in
schema)
  helm lint chart --namespace "${namespace}" >/dev/null
  helm lint chart --namespace "${namespace}" --values "${landscape_overlay}" --values "${cluster_overlay}" >/dev/null
  ;;
schema-negative)
  yq '.global.serviceTree.layer = "notnumeric"' chart/values.yaml >"${tmp}/invalid-values.yaml"
  if helm lint chart --namespace "${namespace}" --values "${tmp}/invalid-values.yaml" >"${tmp}/schema.stdout" 2>"${tmp}/schema.stderr"; then
    echo "❌ non-numeric layer passed Helm schema validation" >&2
    exit 1
  fi
  rg -qi 'layer|pattern|does not match' "${tmp}/schema.stdout" "${tmp}/schema.stderr"
  ;;
schema-drift)
  bash ./scripts/local/generate-chart-schema.sh "${tmp}/values.schema.json" >/dev/null
  cmp chart/values.schema.json "${tmp}/values.schema.json"
  ;;
dependency)
  bash ./scripts/local/vendor-reloader.sh build >/dev/null
  chart_version="$(yq -r '.dependencies[] | select(.name == "reloader") | .version' chart/Chart.yaml)"
  lock_version="$(yq -r '.dependencies[] | select(.name == "reloader") | .version' chart/Chart.lock)"
  app_version="$(yq -r '.appVersion' chart/Chart.yaml)"
  evidence_version="$(yq -r '.chart.version' chart/upstream-evidence.yaml)"
  evidence_app="$(yq -r '.chart.appVersion' chart/upstream-evidence.yaml)"
  archive="chart/charts/reloader-${chart_version}.tgz"
  [ "${chart_version}" != "${lock_version}" ] && echo "❌ Chart.yaml and Chart.lock dependency versions differ" >&2 && exit 1
  [ "${chart_version}" != "${evidence_version}" ] && echo "❌ selected chart and upstream evidence versions differ" >&2 && exit 1
  [ "${app_version}" != "${evidence_app}" ] && echo "❌ selected app and upstream evidence versions differ" >&2 && exit 1
  [ "$(find chart/charts -maxdepth 1 -type f -name 'reloader-*.tgz' | wc -l)" -ne 1 ] && echo "❌ vendored reloader archive inventory is not singular" >&2 && exit 1
  [ ! -s "${archive}" ] && echo "❌ vendored reloader archive is missing" >&2 && exit 1
  [ "$(sha256sum "${archive}" | awk '{print $1}')" != "$(yq -r '.chart.sourceArchiveSha256' chart/upstream-evidence.yaml)" ] && echo "❌ vendored reloader archive hash drifted from recorded upstream" >&2 && exit 1
  ;;
upstream)
  bash ./scripts/local/latest-chart-upstreams.sh
  ;;
lint)
  helm lint chart --namespace "${namespace}"
  echo "🔎 linting landscape+cluster stack"
  helm lint chart --namespace "${namespace}" --values "${landscape_overlay}" --values "${cluster_overlay}"
  ;;
render)
  stacks_render "${tmp}/render"
  # Container names and DNS-1123 object names must be valid RFC-1123 labels/
  # subdomains — kubeconform does not enforce this, but the API server does.
  # RBAC object names legitimately use extra dashes and are exempt from the
  # object-name check.
  for f in "${tmp}/render-base.yaml" "${tmp}/render-stack.yaml"; do
    yq eval-all -o=json '.' "${f}" | jq -se '
      def dnslabel: test("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$");
      def dnssubdomain: test("^[a-z0-9]([-a-z0-9.]*[a-z0-9])?$");
      ["Deployment","StatefulSet","DaemonSet","Job","Service","ConfigMap","Secret","ServiceAccount"] as $dns
      | (map(select(type == "object" and has("kind")))) as $r
      | (all($r[] | select(.kind as $k | $dns | index($k)); (.metadata.name // "") | dnssubdomain))
        and (all($r[] | select(.kind == "Deployment" or .kind == "StatefulSet" or .kind == "DaemonSet" or .kind == "Job");
              (((.spec.template.spec.containers // []) + (.spec.template.spec.initContainers // []))
               | [.[] | select((.name // "") | dnslabel | not)] | length) == 0))
    ' >/dev/null || {
      echo "❌ rendered a non-RFC-1123 workload/service object or container name in ${f}" >&2
      exit 1
    }
  done
  ;;
labels)
  yq -e '.global.serviceTree | has("platform") | not' chart/values.yaml >/dev/null
  # The static deployment labels must stay consistent with the serviceTree source of truth.
  yq -e '.reloader.reloader.deployment.labels."atomi.cloud/service" == .global.serviceTree.service
    and .reloader.reloader.deployment.labels."atomi.cloud/module" == .global.serviceTree.module
    and .reloader.reloader.deployment.labels."atomi.cloud/layer" == .global.serviceTree.layer' chart/values.yaml >/dev/null
  helm template "${release}" chart --namespace "${namespace}" --values "${landscape_overlay}" >"${tmp}/rendered.yaml"
  yq eval-all -o=json '.' "${tmp}/rendered.yaml" | jq --arg ns "${namespace}" -se '
    def lpsm($prefix; $namespace):
      (.[$prefix + "/platform"] == $namespace)
      and (.[$prefix + "/service"] == "chlorine")
      and (.[$prefix + "/module"] == "reloader")
      and (.[$prefix + "/layer"] == "1")
      and (.[$prefix + "/landscape"] == "example");
    def staticlpsm($prefix):
      (.[$prefix + "/service"] == "chlorine")
      and (.[$prefix + "/module"] == "reloader")
      and (.[$prefix + "/layer"] == "1")
      and (.[$prefix + "/landscape"] == "example");
    (map(select(type == "object" and has("kind")))) as $resources
    | ($resources | map(select(.kind == "ConfigMap" and .metadata.name == "chlorine-lpsm"))) as $configmaps
    | ($resources | map(select(.kind == "Deployment"))) as $deployments
    | ($configmaps | length) == 1
      and ($deployments | length) == 1
      and ($configmaps[0].metadata.labels | lpsm("atomi.cloud"; $ns))
      and ($configmaps[0].metadata.annotations | lpsm("atomi.cloud"; $ns))
      and (all($deployments[]; .metadata.labels | staticlpsm("atomi.cloud")))
  ' >/dev/null
  # Namespace change moves the platform label on the wrapper projection.
  helm template "${release}" chart --namespace tenant --values "${landscape_overlay}" >"${tmp}/ns.yaml"
  yq eval-all -o=json '.' "${tmp}/ns.yaml" | jq -se '
    (map(select(type == "object" and .kind == "ConfigMap" and .metadata.name == "chlorine-lpsm"))[0]) as $cm
    | $cm.metadata.labels["atomi.cloud/platform"] == "tenant"
  ' >/dev/null
  # labelPrefix override reprefixes the wrapper projection and leaves no atomi.cloud key.
  helm template "${release}" chart --namespace tenant --values "${landscape_overlay}" --set global.labelPrefix=example.dev >"${tmp}/override.yaml"
  yq eval-all -o=json '.' "${tmp}/override.yaml" | jq -se '
    def lpsm:
      (. ["example.dev/platform"] == "tenant")
      and (. ["example.dev/service"] == "chlorine")
      and (. ["example.dev/module"] == "reloader")
      and (. ["example.dev/layer"] == "1")
      and (. ["example.dev/landscape"] == "example");
    (map(select(type == "object" and .kind == "ConfigMap" and .metadata.name == "chlorine-lpsm"))[0]) as $cm
    | ($cm.metadata.labels | lpsm)
      and ($cm.metadata.annotations | lpsm)
      and ([$cm.metadata.labels, $cm.metadata.annotations] | map(to_entries[]) | map(select(.key | startswith("atomi.cloud/"))) | length) == 0
  ' >/dev/null
  # A duplicate free platform value is rejected at render time.
  if helm template "${release}" chart --namespace tenant --values "${landscape_overlay}" --set global.serviceTree.platform=wrong >/dev/null 2>&1; then
    echo "❌ a duplicate free platform value was accepted" >&2
    exit 1
  fi
  ;;
reloader)
  helm template "${release}" chart --namespace "${namespace}" --values "${landscape_overlay}" >"${tmp}/default.yaml"
  yq eval-all -o=json '.' "${tmp}/default.yaml" | jq -se '
    map(select(type == "object" and .kind == "Deployment"))
    | length == 1
      and all(.[]; .metadata.annotations["reloader.stakater.com/auto"] == "true")
  ' >/dev/null
  # Stateful/unsafe workloads opt out via the values flag.
  helm template "${release}" chart --namespace "${namespace}" --values "${landscape_overlay}" \
    --set-string reloader.reloader.deployment.annotations."reloader\.stakater\.com/auto"=false >"${tmp}/optout.yaml"
  yq eval-all -o=json '.' "${tmp}/optout.yaml" | jq -se '
    map(select(type == "object" and .kind == "Deployment"))
    | length == 1
      and all(.[]; .metadata.annotations["reloader.stakater.com/auto"] == "false")
  ' >/dev/null
  ;;
auto-reload-all)
  # chlorine is annotation OPT-IN, never auto-reload-all: the values flag is false
  # and the controller renders no --auto-reload-all argument.
  yq -e '.reloader.reloader.autoReloadAll == false' chart/values.yaml >/dev/null
  helm template "${release}" chart --namespace "${namespace}" --values "${landscape_overlay}" >"${tmp}/off.yaml"
  if rg -q -- '--auto-reload-all' "${tmp}/off.yaml"; then
    echo "❌ chlorine rendered the --auto-reload-all argument with the opt-in default" >&2
    exit 1
  fi
  # Negative: flipping the flag injects the argument, so the hygiene gate is exercised.
  helm template "${release}" chart --namespace "${namespace}" --values "${landscape_overlay}" \
    --set reloader.reloader.autoReloadAll=true >"${tmp}/on.yaml"
  if ! rg -q -- '--auto-reload-all' "${tmp}/on.yaml"; then
    echo "❌ auto-reload-all negative fixture did not inject the argument; the gate is not exercised" >&2
    exit 1
  fi
  ;;
fullname)
  # Every rendered DNS-subdomain object follows the <service>-<token> fullname
  # convention (exactly one dash, dash-less token). RBAC objects legitimately
  # carry extra dashes and are exempt.
  helm template "${release}" chart --namespace "${namespace}" --values "${landscape_overlay}" >"${tmp}/render.yaml"
  yq eval-all -o=json '.' "${tmp}/render.yaml" | jq -se '
    ["Deployment","StatefulSet","DaemonSet","Job","Service","ConfigMap","Secret","ServiceAccount"] as $dns
    | (map(select(type == "object" and has("kind"))))
    | all(.[] | select(.kind as $k | $dns | index($k)); (.metadata.name // "") | test("^[a-z0-9]+-[a-z0-9]+$"))
  ' >/dev/null
  # Negative: a two-dash fullname override breaks the one-dash convention.
  if helm template "${release}" chart --namespace "${namespace}" --values "${landscape_overlay}" \
    --set reloader.fullnameOverride=chlorine-reloader-x >"${tmp}/bad.yaml" &&
    yq eval-all -o=json '.' "${tmp}/bad.yaml" | jq -se '
      ["Deployment","StatefulSet","DaemonSet","Job","Service","ConfigMap","Secret","ServiceAccount"] as $dns
      | (map(select(type == "object" and has("kind"))))
      | all(.[] | select(.kind as $k | $dns | index($k)); (.metadata.name // "") | test("^[a-z0-9]+-[a-z0-9]+$"))
    ' >/dev/null 2>&1; then
    echo "❌ a two-dash fullname override was accepted by the fullname convention gate" >&2
    exit 1
  fi
  ;;
rendered-manifests)
  for spec in "base::" "stack:${landscape_overlay}:${cluster_overlay}"; do
    label="${spec%%:*}"
    helm_args=()
    IFS=':' read -r _ o1 o2 <<<"${spec}"
    [ -n "${o1}" ] && helm_args+=(--values "${o1}")
    [ -n "${o2}" ] && helm_args+=(--values "${o2}")
    helm template "${release}" chart --namespace "${namespace}" "${helm_args[@]}" >"${tmp}/${label}.yaml"
    kubeconform -strict -summary -ignore-missing-schemas "${tmp}/${label}.yaml"
    yq eval-all 'select(.kind == "Deployment" or .kind == "StatefulSet" or .kind == "DaemonSet" or .kind == "Job" or .kind == "Service")' "${tmp}/${label}.yaml" >"${tmp}/${label}-vap.yaml"
    kyverno apply policies/vap --resource "${tmp}/${label}-vap.yaml" --detailed-results --remove-color
  done
  ;;
vap-sabotage)
  helm template "${release}" chart --namespace "${namespace}" --values "${landscape_overlay}" --set-string reloader.image.tag=latest >"${tmp}/rendered.yaml" 2>/dev/null
  yq eval-all 'select(.kind == "Deployment" or .kind == "Service")' "${tmp}/rendered.yaml" >"${tmp}/vap-resources.yaml"
  if kyverno apply policies/vap --resource "${tmp}/vap-resources.yaml" --remove-color >/dev/null 2>&1; then
    echo "❌ :latest wiring sabotage was not caught by the VAP stage" >&2
    exit 1
  fi
  ;;
publish-git)
  PUBLISH_MODE=git PUBLISH_DRY_RUN=true RELEASE_VERSION=v0.1.0 PUBLISH_OUTPUT_DIR="${tmp}/git" bash ./scripts/ci/publish.sh >/dev/null
  [ ! -s "${tmp}/git/diene-chlorine-0.1.0.tgz" ] && echo "❌ git chart package missing" >&2 && exit 1
  [ ! -s "${tmp}/git/index.yaml" ] && echo "❌ git chart index missing" >&2 && exit 1
  ;;
publish-oci)
  PUBLISH_MODE=oci PUBLISH_DRY_RUN=true RELEASE_VERSION=v0.1.0 PUBLISH_OUTPUT_DIR="${tmp}/oci" bash ./scripts/ci/publish.sh >/dev/null
  [ ! -s "${tmp}/oci/diene-chlorine-0.1.0.tgz" ] && echo "❌ OCI chart package missing" >&2 && exit 1
  rg -q '^oci://registry.example.invalid/charts$' "${tmp}/oci/oci-ref.txt"
  ;;
version)
  PUBLISH_MODE=git PUBLISH_DRY_RUN=true RELEASE_VERSION=v0.1.0 PUBLISH_OUTPUT_DIR="${tmp}/version" bash ./scripts/ci/publish.sh >/dev/null
  if PUBLISH_MODE=git PUBLISH_DRY_RUN=true RELEASE_VERSION=v0.2.0 PUBLISH_OUTPUT_DIR="${tmp}/version-bad" bash ./scripts/ci/publish.sh >/dev/null 2>&1; then
    echo "❌ version==tag guard did not red on a mismatched tag" >&2
    exit 1
  fi
  ;;
presence)
  test -s docs/developer/chlorine-baseline.md
  test -s chart/upstream-evidence.yaml
  test -s chart/templates/lpsm-configmap.yaml
  test -s policies/vap/workload-baseline.yaml
  test -s policies/vap/service-baseline.yaml
  test -x scripts/local/vendor-reloader.sh
  test -x scripts/validate/chlorine-k3d.sh
  ;;
*)
  echo "❌ unknown validation mode '${mode}'" >&2
  exit 1
  ;;
esac

echo "✅ Chlorine ${mode} validation passed"
