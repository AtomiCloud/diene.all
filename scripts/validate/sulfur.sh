#!/usr/bin/env bash
# sulfur cert-manager engine — unit-tier testing pyramid (S30 / Q-I27).
#
# sulfur is a materialized chart PRODUCT: it inherits the helm-wrapper *shape*
# but not the probe obligation. Evidence is an ordinary testing pyramid with
# negative fixtures as normal tests. This script owns the unit tier
# (lint/render/schema/static conformance); the k3d integration tier lives in
# sulfur-k3d.sh.
set -euo pipefail

mode="${1:-}"
release="${RELEASE:-sulfur}"
namespace="${NAMESPACE:-sample}"
label_prefix="${LABEL_PREFIX:-atomi.cloud}"
tmp="$(mktemp -d)"
trap 'rm -rf "${tmp}"' EXIT

[ -z "${mode}" ] && echo "❌ validation mode not set" >&2 && exit 1

render() {
  helm template "${release}" chart --namespace "${namespace}" "$@"
}

# Render every committed values stack (base -> landscape -> cluster).
render_all() {
  render >/dev/null
  render --values chart/values.example.yaml >/dev/null
  render --values chart/values.example.yaml --values chart/values.lapras.yaml >/dev/null
}

assert_gateway_api_enabled() {
  local values_file="$1" cfg up
  cfg="$(yq -r '.config.enableGatewayAPI' "$values_file")"
  up="$(yq -r '.upstream.config.enableGatewayAPI' "$values_file")"
  [ "$cfg" = "true" ] && [ "$up" = "true" ]
}

assert_label_prefix_sync() {
  # Subchart values cannot call templates, so labelPrefix is statically mirrored
  # into upstream.global.commonLabels. The mirror must stay in sync with the one
  # configurable labelPrefix (never hard-coded independently).
  local values_file="$1" prefix mirror
  prefix="$(yq -r '.labelPrefix' "$values_file")"
  mirror="$(yq -r '.upstream.global.commonLabels | keys[]' "$values_file" | sed -n 's|^\(.*\)/[^/]*$|\1|p' | sort -u)"
  [ -n "$prefix" ] && [ "$mirror" = "$prefix" ]
}

assert_no_dead_feature_gate() {
  # ExperimentalGatewayAPISupport was removed in cert-manager v1.15; the
  # canonical knob is config.enableGatewayAPI. The dead flag must never appear.
  local values_file="$1"
  ! rg -q 'ExperimentalGatewayAPISupport' "$values_file"
}

case "${mode}" in
schema)
  helm lint chart --namespace "${namespace}" >/dev/null
  helm lint chart --namespace "${namespace}" --values chart/values.example.yaml >/dev/null
  helm lint chart --namespace "${namespace}" --values chart/values.example.yaml --values chart/values.lapras.yaml >/dev/null
  ;;

schema-drift)
  ./scripts/local/generate-chart-schema.sh "${tmp}/values.schema.json" >/dev/null
  cmp chart/values.schema.json "${tmp}/values.schema.json"
  ;;

lint)
  helm lint chart --namespace "${namespace}"
  helm lint chart --namespace "${namespace}" --values chart/values.example.yaml
  helm lint chart --namespace "${namespace}" --values chart/values.example.yaml --values chart/values.lapras.yaml
  ;;

render)
  render_all
  ;;

labels)
  # LPSM identity is stamped onto every rendered cert-manager resource via
  # upstream.global.commonLabels (subchart values cannot call templates). The
  # labelPrefix is a single configurable value; the mirror in commonLabels must
  # stay in sync with it (drift invariant).
  render --values chart/values.example.yaml --values chart/values.lapras.yaml >"${tmp}/rendered.yaml"
  yq eval-all -o=json '.' "${tmp}/rendered.yaml" |
    jq -s -e --arg p "${label_prefix}" \
      'map(select(.kind != null)) | length > 0 and all(.[]; (.metadata.labels[$p + "/service"] == "sulfur") and (.metadata.labels[$p + "/module"] == "certs") and (.metadata.labels[$p + "/layer"] == "1") and (.metadata.labels[$p + "/platform"] == "sample") and (.metadata.labels[$p + "/landscape"] == "example") and (.metadata.labels[$p + "/cluster"] == "lapras"))' >/dev/null
  assert_label_prefix_sync chart/values.yaml || {
    echo "❌ labelPrefix/commonLabels drift in base values" >&2
    exit 1
  }
  # Negative fixture: changing labelPrefix alone must be caught as drift.
  yq -o=yaml '.labelPrefix = "example.dev"' chart/values.yaml >"${tmp}/drift.yaml"
  if assert_label_prefix_sync "${tmp}/drift.yaml"; then
    echo "❌ label drift check missed a labelPrefix/commonLabels mismatch" >&2
    exit 1
  fi
  ;;

reloader)
  # Reloader opt-in is baked onto every long-running cert-manager workload
  # (controller/cainjector/webhook). The one-shot startupapicheck Job is excluded.
  render >"${tmp}/default.yaml"
  yq eval-all -o=json '.' "${tmp}/default.yaml" |
    jq -s -e 'map(select(.kind == "Deployment" or .kind == "StatefulSet" or .kind == "DaemonSet")) | length == 3 and all(.[]; .spec.template.metadata.annotations["reloader.stakater.com/auto"] == "true")' >/dev/null
  # Opt-out path: a values overlay nulling the upstream podAnnotations drops the
  # annotation from every workload.
  cat >"${tmp}/optout.yaml" <<'YAML'
upstream:
  podAnnotations:
    reloader.stakater.com/auto: null
  webhook:
    podAnnotations:
      reloader.stakater.com/auto: null
  cainjector:
    podAnnotations:
      reloader.stakater.com/auto: null
YAML
  render --values "${tmp}/optout.yaml" >"${tmp}/optout-rendered.yaml"
  yq eval-all -o=json '.' "${tmp}/optout-rendered.yaml" |
    jq -s -e 'map(select(.kind == "Deployment")) | all(.[]; .spec.template.metadata.annotations["reloader.stakater.com/auto"] == null)' >/dev/null
  ;;

rendered-manifests)
  # Q-G20 — inherited rendered-manifest validation stage:
  # helm template -> kubeconform (k8s schemas) -> kyverno apply VAP eval.
  # The six cert-manager CRD *definitions* are upstream-authoritative and skipped
  # (they cannot validate against themselves); every native resource is checked.
  render >"${tmp}/rendered.yaml"
  kubeconform -strict -summary -skip CustomResourceDefinition -schema-location default "${tmp}/rendered.yaml"
  yq eval-all 'select(.kind == "Deployment" or .kind == "StatefulSet" or .kind == "DaemonSet" or .kind == "Job" or .kind == "Service")' "${tmp}/rendered.yaml" >"${tmp}/vap-resources.yaml"
  kyverno apply policies/vap --resource "${tmp}/vap-resources.yaml" --detailed-results --remove-color
  # ONE wiring sabotage (Q-G20): a :latest workload image must redden the stage.
  sed 's|cert-manager-controller:v1.20.3|cert-manager-controller:latest|' "${tmp}/rendered.yaml" |
    yq eval-all 'select(.kind == "Deployment" or .kind == "Job")' >"${tmp}/sabotage.yaml"
  if kyverno apply policies/vap --resource "${tmp}/sabotage.yaml" --remove-color >/dev/null 2>&1; then
    echo "❌ :latest wiring sabotage was not caught" >&2
    exit 1
  fi
  ;;

sequential-minor)
  # Q-G22 — cert-manager sequential-minor gate (chart-repo CI check).
  # Positive steps: patch, same, and exactly-one-minor advances all pass.
  ./scripts/validate/sequential-minor.sh v1.20.3 v1.20.3 >/dev/null
  ./scripts/validate/sequential-minor.sh v1.20.3 v1.20.5 >/dev/null
  ./scripts/validate/sequential-minor.sh v1.20.0 v1.21.0 >/dev/null
  ./scripts/validate/sequential-minor.sh v1.19.0 v1.20.0 >/dev/null
  # Negative fixtures: a 2-minor skip and a major skip must both go red.
  if ./scripts/validate/sequential-minor.sh v1.20.3 v1.22.0 >/dev/null 2>&1; then
    echo "❌ sequential-minor gate accepted a 2-minor skip (v1.20 → v1.22)" >&2
    exit 1
  fi
  if ./scripts/validate/sequential-minor.sh v1.20.3 v2.0.0 >/dev/null 2>&1; then
    echo "❌ sequential-minor gate accepted a major skip" >&2
    exit 1
  fi
  ./scripts/validate/sequential-minor.sh --pin chart >/dev/null
  ;;

gateway-api)
  # Gateway API support is required (kgateway integration). The canonical knob
  # is upstream.config.enableGatewayAPI; config.enableGatewayAPI is the static
  # mirror. Both must be true and a disabled flag must be caught.
  assert_gateway_api_enabled chart/values.yaml || {
    echo "❌ Gateway API not enabled in base values" >&2
    exit 1
  }
  yq -o=yaml '.upstream.config.enableGatewayAPI = false | .config.enableGatewayAPI = false' chart/values.yaml >"${tmp}/no-gateway.yaml"
  if assert_gateway_api_enabled "${tmp}/no-gateway.yaml"; then
    echo "❌ gateway-api check missed a disabled flag" >&2
    exit 1
  fi
  ;;

no-dead-flag)
  # ExperimentalGatewayAPISupport is dead since v1.15; it must never appear.
  assert_no_dead_feature_gate chart/values.yaml || {
    echo "❌ dead ExperimentalGatewayAPISupport flag present" >&2
    exit 1
  }
  assert_no_dead_feature_gate chart/values.example.yaml
  assert_no_dead_feature_gate chart/values.lapras.yaml
  printf 'upstream:\n  featureGates: "ExperimentalGatewayAPISupport=true"\n' >"${tmp}/dead-flag.yaml"
  if assert_no_dead_feature_gate "${tmp}/dead-flag.yaml"; then
    echo "❌ dead-flag check missed ExperimentalGatewayAPISupport" >&2
    exit 1
  fi
  ;;

no-issuer)
  # Pure-passthrough invariant: sulfur owns the engine ONLY. Issuer/ClusterIssuer
  # *instances* live in zinc; sulfur ships neither (only the upstream CRD
  # definitions render). A synthesized Issuer template must be caught.
  if rg -q 'kind:[[:space:]]*(Cluster)?Issuer\b' chart/templates/; then
    echo "❌ sulfur ships an Issuer/ClusterIssuer template (issuers live in zinc)" >&2
    exit 1
  fi
  mkdir -p "${tmp}/chart/templates"
  cp -r chart/. "${tmp}/chart/"
  printf 'apiVersion: cert-manager.io/v1\nkind: ClusterIssuer\nmetadata:\n  name: forbidden\nspec:\n  selfSigned: {}\n' >"${tmp}/chart/templates/issuer-fixture.yaml"
  rg -q 'kind:[[:space:]]*(Cluster)?Issuer\b' "${tmp}/chart/templates/" || {
    echo "❌ boundary check missed a synthesized Issuer template" >&2
    exit 1
  }
  ;;

crds)
  # CRDs are installed by the engine chart (crds.enabled) and kept on uninstall
  # (crds.keep) so certificates survive. Disabling the flag drops every CRD.
  [ "$(yq -r '.upstream.crds.enabled' chart/values.yaml)" = "true" ] || {
    echo "❌ upstream.crds.enabled is not true" >&2
    exit 1
  }
  [ "$(yq -r '.upstream.crds.keep' chart/values.yaml)" = "true" ] || {
    echo "❌ upstream.crds.keep is not true" >&2
    exit 1
  }
  render >"${tmp}/with-crds.yaml"
  [ "$(rg -c '^kind: CustomResourceDefinition$' "${tmp}/with-crds.yaml")" -gt 0 ] || {
    echo "❌ no CRDs rendered with crds.enabled=true" >&2
    exit 1
  }
  # Negative fixture: crds.enabled=false must render zero CRD definitions.
  render --set upstream.crds.enabled=false >"${tmp}/no-crds.yaml"
  if rg -q '^kind: CustomResourceDefinition$' "${tmp}/no-crds.yaml"; then
    echo "❌ CRDs still rendered with crds.enabled=false" >&2
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
  ;;

presence)
  test -s docs/developer/sulfur-baseline.md
  test -s chart/templates/_helpers.tpl
  test -s policies/vap/workload-baseline.yaml
  test -s policies/vap/service-baseline.yaml
  rg -q '^## Tokenization surface$' docs/developer/sulfur-baseline.md
  ;;

*)
  echo "❌ unknown validation mode '${mode}'" >&2
  exit 1
  ;;
esac

echo "✅ sulfur ${mode} validation passed"
