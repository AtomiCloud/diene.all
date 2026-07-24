#!/usr/bin/env bash
# Sulfur unit-tier validation (materialized cert-manager engine wrapper — S30, no
# probe matrix). One mode per independently invoked mechanism; the CI
# orchestrator calls them in order. Positive assertion and its negative fixture
# live together in each mode.
set -euo pipefail

mode="${1:-}"
release="${RELEASE:-sulfur}"
namespace="${NAMESPACE:-cert-manager}"
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
  bash ./scripts/local/vendor-cert-manager.sh build >/dev/null
  chart_version="$(yq -r '.dependencies[] | select(.name == "cert-manager") | .version' chart/Chart.yaml)"
  lock_version="$(yq -r '.dependencies[] | select(.name == "cert-manager") | .version' chart/Chart.lock)"
  app_version="$(yq -r '.appVersion' chart/Chart.yaml)"
  evidence_version="$(yq -r '.chart.version' chart/upstream-evidence.yaml)"
  evidence_app="$(yq -r '.chart.appVersion' chart/upstream-evidence.yaml)"
  archive="chart/charts/cert-manager-${chart_version}.tgz"
  [ "${chart_version}" != "${lock_version}" ] && echo "❌ Chart.yaml and Chart.lock dependency versions differ" >&2 && exit 1
  [ "${chart_version}" != "${evidence_version}" ] && echo "❌ selected chart and upstream evidence versions differ" >&2 && exit 1
  [ "${app_version}" != "${evidence_app}" ] && echo "❌ selected app and upstream evidence versions differ" >&2 && exit 1
  [ "$(find chart/charts -maxdepth 1 -type f -name 'cert-manager-*.tgz' | wc -l)" -ne 1 ] && echo "❌ vendored cert-manager archive inventory is not singular" >&2 && exit 1
  [ ! -s "${archive}" ] && echo "❌ vendored cert-manager archive is missing" >&2 && exit 1
  [ "$(sha256sum "${archive}" | awk '{print $1}')" != "$(yq -r '.chart.sourceArchiveSha256' chart/upstream-evidence.yaml)" ] && echo "❌ vendored cert-manager archive hash drifted from recorded upstream" >&2 && exit 1
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
  # subdomains — kubeconform does not enforce this, but the API server does (the
  # aliased dependency once leaked an uppercase container name). RBAC/CRD/webhook
  # object names legitimately use colons and are exempt from the object-name check.
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
  # commonLabels must stay consistent with the serviceTree source of truth.
  yq -e '.global.commonLabels."atomi.cloud/service" == .global.serviceTree.service
    and .global.commonLabels."atomi.cloud/module" == .global.serviceTree.module
    and .global.commonLabels."atomi.cloud/layer" == .global.serviceTree.layer' chart/values.yaml >/dev/null
  helm template "${release}" chart --namespace "${namespace}" --values "${landscape_overlay}" >"${tmp}/rendered.yaml"
  yq eval-all -o=json '.' "${tmp}/rendered.yaml" | jq --arg ns "${namespace}" -se '
    def lpsm($prefix; $namespace):
      (.[$prefix + "/platform"] == $namespace)
      and (.[$prefix + "/service"] == "sulfur")
      and (.[$prefix + "/module"] == "certs")
      and (.[$prefix + "/layer"] == "1")
      and (.[$prefix + "/landscape"] == "example");
    def commonlpsm($prefix):
      (.[$prefix + "/service"] == "sulfur")
      and (.[$prefix + "/module"] == "certs")
      and (.[$prefix + "/layer"] == "1")
      and (.[$prefix + "/landscape"] == "example");
    (map(select(type == "object" and has("kind")))) as $resources
    | ($resources | map(select(.kind == "ConfigMap" and .metadata.name == "sulfur-lpsm"))) as $configmaps
    | ($resources | map(select(.kind == "Deployment"))) as $deployments
    | ($configmaps | length) == 1
      and ($deployments | length) == 3
      and ($configmaps[0].metadata.labels | lpsm("atomi.cloud"; $ns))
      and ($configmaps[0].metadata.annotations | lpsm("atomi.cloud"; $ns))
      and (all($deployments[]; .metadata.labels | commonlpsm("atomi.cloud")))
  ' >/dev/null
  # Namespace change moves the platform label on the wrapper projection.
  helm template "${release}" chart --namespace tenant --values "${landscape_overlay}" >"${tmp}/ns.yaml"
  yq eval-all -o=json '.' "${tmp}/ns.yaml" | jq -se '
    (map(select(type == "object" and .kind == "ConfigMap" and .metadata.name == "sulfur-lpsm"))[0]) as $cm
    | $cm.metadata.labels["atomi.cloud/platform"] == "tenant"
  ' >/dev/null
  # labelPrefix override reprefixes the wrapper projection and leaves no atomi.cloud key.
  helm template "${release}" chart --namespace tenant --values "${landscape_overlay}" --set global.labelPrefix=example.dev >"${tmp}/override.yaml"
  yq eval-all -o=json '.' "${tmp}/override.yaml" | jq -se '
    def lpsm:
      (. ["example.dev/platform"] == "tenant")
      and (. ["example.dev/service"] == "sulfur")
      and (. ["example.dev/module"] == "certs")
      and (. ["example.dev/layer"] == "1")
      and (. ["example.dev/landscape"] == "example");
    (map(select(type == "object" and .kind == "ConfigMap" and .metadata.name == "sulfur-lpsm"))[0]) as $cm
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
    | length == 3
      and all(.[]; .metadata.annotations["reloader.stakater.com/auto"] == "true")
  ' >/dev/null
  helm template "${release}" chart --namespace "${namespace}" --values "${landscape_overlay}" \
    --set-string certmanager.deploymentAnnotations."reloader\.stakater\.com/auto"=false \
    --set-string certmanager.webhook.deploymentAnnotations."reloader\.stakater\.com/auto"=false \
    --set-string certmanager.cainjector.deploymentAnnotations."reloader\.stakater\.com/auto"=false >"${tmp}/optout.yaml"
  yq eval-all -o=json '.' "${tmp}/optout.yaml" | jq -se '
    map(select(type == "object" and .kind == "Deployment"))
    | length == 3
      and all(.[]; .metadata.annotations["reloader.stakater.com/auto"] == "false")
  ' >/dev/null
  ;;
gateway-api)
  # Positive: the stable Gateway API config field is enabled in the rendered controller config.
  helm template "${release}" chart --namespace "${namespace}" --values "${landscape_overlay}" >"${tmp}/on.yaml"
  yq eval-all -o=json '.' "${tmp}/on.yaml" | jq -se '
    map(select(type == "object" and .kind == "ConfigMap" and .metadata.name == "cert-manager"))[0].data["config.yaml"]
    | test("enableGatewayAPI:\\s*true")
  ' >/dev/null
  # Negative: disabling the flag must red the same assertion.
  helm template "${release}" chart --namespace "${namespace}" --values "${landscape_overlay}" \
    --set certmanager.config.enableGatewayAPI=false >"${tmp}/off.yaml"
  if yq eval-all -o=json '.' "${tmp}/off.yaml" | jq -se '
    map(select(type == "object" and .kind == "ConfigMap" and .metadata.name == "cert-manager"))[0].data["config.yaml"]
    | test("enableGatewayAPI:\\s*true")
  ' >/dev/null 2>&1; then
    echo "❌ disabling config.enableGatewayAPI did not red the Gateway API gate" >&2
    exit 1
  fi
  ;;
dead-flag)
  # Static hygiene: the dead ExperimentalGatewayAPISupport gate must not appear as
  # a values key/value (yq drops comments, so the explanatory comment is ignored).
  for vf in chart/values.yaml chart/values.example.yaml chart/values.lapras.yaml; do
    if yq -o=json '.' "${vf}" | rg -q 'ExperimentalGatewayAPISupport'; then
      echo "❌ dead ExperimentalGatewayAPISupport feature gate present in ${vf}" >&2
      exit 1
    fi
  done
  helm template "${release}" chart --namespace "${namespace}" --values "${landscape_overlay}" >"${tmp}/clean.yaml"
  if rg -q 'ExperimentalGatewayAPISupport' "${tmp}/clean.yaml"; then
    echo "❌ dead ExperimentalGatewayAPISupport feature gate present in rendered output" >&2
    exit 1
  fi
  # Negative: injecting the dead gate must be catchable by the same grep.
  helm template "${release}" chart --namespace "${namespace}" --values "${landscape_overlay}" \
    --set certmanager.config.featureGates.ExperimentalGatewayAPISupport=true >"${tmp}/dirty.yaml"
  if ! rg -q 'ExperimentalGatewayAPISupport' "${tmp}/dirty.yaml"; then
    echo "❌ dead-flag negative fixture did not inject the gate; hygiene gate is not exercised" >&2
    exit 1
  fi
  ;;
issuer-boundary)
  # The wrapper owns no Issuer/ClusterIssuer template.
  if rg -q '^kind:\s*(Issuer|ClusterIssuer)\s*$' chart/templates/*.yaml; then
    echo "❌ wrapper template defines an Issuer/ClusterIssuer (engine/issuer split violated)" >&2
    exit 1
  fi
  helm template "${release}" chart --namespace "${namespace}" --values "${landscape_overlay}" >"${tmp}/render.yaml"
  boundary_count() {
    yq eval-all -o=json '.' "$1" | jq -s '[.[] | select(type == "object" and (.kind == "Issuer" or .kind == "ClusterIssuer"))] | length'
  }
  [ "$(boundary_count "${tmp}/render.yaml")" -ne 0 ] && echo "❌ rendered wrapper emits an Issuer/ClusterIssuer instance" >&2 && exit 1
  # Negative: a wrapper Issuer template makes the boundary checker red.
  cat >chart/templates/zz-boundary-fixture.yaml <<'FIXTURE'
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: sulfur-boundary-fixture
spec:
  selfSigned: {}
FIXTURE
  trap 'rm -f chart/templates/zz-boundary-fixture.yaml; rm -rf "${tmp}"' EXIT
  helm template "${release}" chart --namespace "${namespace}" --values "${landscape_overlay}" >"${tmp}/fixture.yaml"
  if [ "$(boundary_count "${tmp}/fixture.yaml")" -eq 0 ]; then
    echo "❌ issuer-boundary negative fixture did not surface an Issuer instance" >&2
    exit 1
  fi
  rm -f chart/templates/zz-boundary-fixture.yaml
  trap 'rm -rf "${tmp}"' EXIT
  ;;
crds)
  # skipCrds/SSA stance is declared in values.
  yq -e '.certmanager.crds.enabled == true and .certmanager.crds.keep == true' chart/values.yaml >/dev/null
  crd_count() {
    yq eval-all -o=json '.' "$1" | jq -s '[.[] | select(type == "object" and .kind == "CustomResourceDefinition" and (.metadata.name | test("cert-manager[.]io$|acme[.]cert-manager[.]io$")))] | length'
  }
  helm template "${release}" chart --namespace "${namespace}" --values "${landscape_overlay}" >"${tmp}/on.yaml"
  [ "$(crd_count "${tmp}/on.yaml")" -lt 6 ] && echo "❌ crds.enabled=true did not render the cert-manager CRD set" >&2 && exit 1
  # Negative: crds.enabled=false renders no CRDs, reddening the presence assertion.
  helm template "${release}" chart --namespace "${namespace}" --values "${landscape_overlay}" \
    --set certmanager.crds.enabled=false >"${tmp}/off.yaml"
  [ "$(crd_count "${tmp}/off.yaml")" -ne 0 ] && echo "❌ crds.enabled=false still rendered CRDs" >&2 && exit 1
  ;;
sequential-minor)
  bash ./scripts/validate/check-sequential-minor.sh
  if SEQ_PINNED_MINOR=1.22 bash ./scripts/validate/check-sequential-minor.sh >/dev/null 2>&1; then
    echo "❌ a version-skip bump (1.19 -> 1.22) did not red the sequential-minor gate" >&2
    exit 1
  fi
  ;;
rendered-manifests)
  for spec in "base::" "stack:${landscape_overlay}:${cluster_overlay}"; do
    name="${spec%%::*}"
    name="${name%%:*}"
    helm_args=()
    IFS=':' read -r label o1 o2 <<<"${spec}"
    [ -n "${o1}" ] && helm_args+=(--values "${o1}")
    [ -n "${o2}" ] && helm_args+=(--values "${o2}")
    helm template "${release}" chart --namespace "${namespace}" "${helm_args[@]}" >"${tmp}/${label}.yaml"
    kubeconform -strict -summary -ignore-missing-schemas "${tmp}/${label}.yaml"
    yq eval-all 'select(.kind == "Deployment" or .kind == "StatefulSet" or .kind == "DaemonSet" or .kind == "Job" or .kind == "Service")' "${tmp}/${label}.yaml" >"${tmp}/${label}-vap.yaml"
    kyverno apply policies/vap --resource "${tmp}/${label}-vap.yaml" --detailed-results --remove-color
  done
  ;;
vap-sabotage)
  helm template "${release}" chart --namespace "${namespace}" --values "${landscape_overlay}" --set certmanager.image.tag=latest >"${tmp}/rendered.yaml" 2>/dev/null
  yq eval-all 'select(.kind == "Deployment" or .kind == "Service")' "${tmp}/rendered.yaml" >"${tmp}/vap-resources.yaml"
  if kyverno apply policies/vap --resource "${tmp}/vap-resources.yaml" --remove-color >/dev/null 2>&1; then
    echo "❌ :latest wiring sabotage was not caught by the VAP stage" >&2
    exit 1
  fi
  ;;
publish-git)
  PUBLISH_MODE=git PUBLISH_DRY_RUN=true RELEASE_VERSION=v0.1.0 PUBLISH_OUTPUT_DIR="${tmp}/git" bash ./scripts/ci/publish.sh >/dev/null
  [ ! -s "${tmp}/git/diene-sulfur-0.1.0.tgz" ] && echo "❌ git chart package missing" >&2 && exit 1
  [ ! -s "${tmp}/git/index.yaml" ] && echo "❌ git chart index missing" >&2 && exit 1
  ;;
publish-oci)
  PUBLISH_MODE=oci PUBLISH_DRY_RUN=true RELEASE_VERSION=v0.1.0 PUBLISH_OUTPUT_DIR="${tmp}/oci" bash ./scripts/ci/publish.sh >/dev/null
  [ ! -s "${tmp}/oci/diene-sulfur-0.1.0.tgz" ] && echo "❌ OCI chart package missing" >&2 && exit 1
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
  test -s docs/developer/sulfur-baseline.md
  test -s chart/upstream-evidence.yaml
  test -s chart/upgrade-policy.yaml
  test -s chart/templates/lpsm-configmap.yaml
  test -s policies/vap/workload-baseline.yaml
  test -s policies/vap/service-baseline.yaml
  test -x scripts/local/vendor-cert-manager.sh
  test -x scripts/validate/check-sequential-minor.sh
  test -x scripts/validate/sulfur-k3d.sh
  ;;
*)
  echo "❌ unknown validation mode '${mode}'" >&2
  exit 1
  ;;
esac

echo "✅ Sulfur ${mode} validation passed"
