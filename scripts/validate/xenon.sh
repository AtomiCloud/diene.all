#!/usr/bin/env bash
# Xenon unit-tier validation (materialized chart product — no probe matrix).
# One mode per independently invoked mechanism; the CI orchestrator calls them in order.
set -euo pipefail

mode="${1:-}"
release="${RELEASE:-xenon}"
namespace="${NAMESPACE:-sample}"
tmp="$(mktemp -d)"
trap 'rm -rf "${tmp}"' EXIT

[ -z "${mode}" ] && echo "❌ validation mode not set" >&2 && exit 1

case "${mode}" in
schema)
  helm lint chart --namespace "${namespace}" >/dev/null
  helm lint chart --namespace "${namespace}" --values chart/values.example.yaml >/dev/null
  helm lint chart --namespace "${namespace}" --values chart/values.example.yaml --values chart/values.lapras.yaml >/dev/null
  ;;
schema-drift)
  bash ./scripts/local/generate-chart-schema.sh "${tmp}/values.schema.json" >/dev/null
  cmp chart/values.schema.json "${tmp}/values.schema.json"
  ;;
lint)
  helm lint chart --namespace "${namespace}"
  helm lint chart --namespace "${namespace}" --values chart/values.example.yaml
  helm lint chart --namespace "${namespace}" --values chart/values.example.yaml --values chart/values.lapras.yaml
  ;;
render)
  helm template "${release}" chart --namespace "${namespace}" >/dev/null
  helm template "${release}" chart --namespace "${namespace}" --values chart/values.example.yaml >/dev/null
  helm template "${release}" chart --namespace "${namespace}" --values chart/values.example.yaml --values chart/values.lapras.yaml >/dev/null
  ;;
labels)
  helm template "${release}" chart --namespace "${namespace}" --values chart/values.example.yaml >"${tmp}/rendered.yaml"
  yq eval-all -o=json '.' "${tmp}/rendered.yaml" | jq -s -e 'map(select(.kind == "ConfigMap" and .metadata.name == "xenon-lpsm"))[0].metadata.labels | (.["atomi.cloud/platform"] == "sample" and .["atomi.cloud/service"] == "xenon" and .["atomi.cloud/module"] == "metrics" and .["atomi.cloud/layer"] == "1" and .["atomi.cloud/landscape"] == "example")' >/dev/null
  yq eval-all -o=json '.' "${tmp}/rendered.yaml" | jq -s -e 'map(select(.kind == "Deployment" and .metadata.name == "xenon-metrics"))[0].spec.template.metadata.labels | (.["atomi.cloud/platform"] == "sample" and .["atomi.cloud/service"] == "xenon" and .["atomi.cloud/landscape"] == "example")' >/dev/null
  helm template "${release}" chart --namespace "${namespace}" --values chart/values.example.yaml --set labelPrefix=example.dev >"${tmp}/override.yaml"
  yq eval-all -o=json '.' "${tmp}/override.yaml" | jq -s -e 'map(select(.kind == "ConfigMap" and .metadata.name == "xenon-lpsm"))[0].metadata.labels | (.["example.dev/platform"] == "sample" and .["example.dev/service"] == "xenon" and .["atomi.cloud/platform"] == null)' >/dev/null
  ;;
reloader)
  helm template "${release}" chart --namespace "${namespace}" --values chart/values.example.yaml >"${tmp}/default.yaml"
  yq eval-all -o=json '.' "${tmp}/default.yaml" | jq -s -e 'map(select(.kind == "Deployment" and .metadata.name == "xenon-metrics"))[0].spec.template.metadata.annotations["reloader.stakater.com/auto"] == "true"' >/dev/null
  printf 'metricsServer:\n  podAnnotations:\n    reloader.stakater.com/auto: "false"\n' >"${tmp}/optout.yaml"
  helm template "${release}" chart --namespace "${namespace}" --values chart/values.example.yaml --values "${tmp}/optout.yaml" >"${tmp}/optout-render.yaml"
  yq eval-all -o=json '.' "${tmp}/optout-render.yaml" | jq -s -e 'map(select(.kind == "Deployment" and .metadata.name == "xenon-metrics"))[0].spec.template.metadata.annotations["reloader.stakater.com/auto"] == "false"' >/dev/null
  ;;
fullname)
  yq -e '.metricsServer.fullnameOverride | test("^[a-z0-9]+-[a-z0-9]+$")' chart/values.yaml >/dev/null
  helm template "${release}" chart --namespace "${namespace}" --values chart/values.example.yaml >"${tmp}/names.yaml"
  yq eval-all -o=json '.' "${tmp}/names.yaml" | jq -s -e 'map(select(.kind == "ConfigMap") | .metadata.name) | all(.[]; test("^[a-z0-9]+-[a-z0-9]+$"))' >/dev/null
  yq eval-all -o=json '.' "${tmp}/names.yaml" | jq -s -e 'map(select(.kind == "Deployment" or .kind == "Service" or .kind == "ServiceAccount") | .metadata.name) | all(.[]; test("^[a-z0-9]+-[a-z0-9]+$"))' >/dev/null
  ;;
task-surface)
  task --list-all | rg -q 'example:lapras:debug'
  task --list-all | rg -q 'example:lapras:template'
  task --list-all | rg -q 'example:lapras:install'
  task --list-all | rg -q 'example:lapras:remove'
  ;;
toggle-map)
  assert_toggle() {
    local overlay="$1" expected="$2" count actual
    count="$(helm template "${release}" chart --namespace "${namespace}" --values "${overlay}" 2>/dev/null | grep -c "^kind:" || true)"
    [ "${count}" -gt 0 ] && actual=true || actual=false
    [ "${actual}" = "${expected}" ] || {
      echo "❌ toggle mismatch for ${overlay}: expected=${expected} actual=${actual} (count=${count})" >&2
      return 1
    }
  }
  while IFS= read -r entry; do
    overlay="$(printf '%s' "${entry}" | jq -r '.overlay')"
    expected="$(printf '%s' "${entry}" | jq -r '.enabled')"
    assert_toggle "${overlay}" "${expected}"
  done < <(yq -o=json '.overlays[]' chart/toggle-map.yaml | jq -c '.')
  # Negative fixture: flip the lapras overlay ON; the baseline still declares OFF,
  # so the gate MUST go red on the sabotaged overlay.
  yq '.metricsServer.enabled = true' chart/values.lapras.yaml >"${tmp}/sabotage.yaml"
  if assert_toggle "${tmp}/sabotage.yaml" false 2>/dev/null; then
    echo "❌ negative fixture: lapras-flipped-ON was accepted as OFF" >&2
    exit 1
  fi
  yq -e '.overlays[] | select(.environment == "lapras") | .enabled == false' chart/toggle-map.yaml >/dev/null
  ;;
rendered-manifests)
  helm template "${release}" chart --namespace "${namespace}" --values chart/values.example.yaml >"${tmp}/rendered.yaml"
  kubeconform -strict -summary "${tmp}/rendered.yaml"
  yq eval-all 'select(.kind == "Deployment" or .kind == "StatefulSet" or .kind == "DaemonSet" or .kind == "Job" or .kind == "Service")' "${tmp}/rendered.yaml" >"${tmp}/vap-resources.yaml"
  kyverno apply policies/vap --resource "${tmp}/vap-resources.yaml" --detailed-results --remove-color
  ;;
vap-sabotage)
  helm template "${release}" chart --namespace "${namespace}" --values chart/values.example.yaml --set metricsServer.image.tag=latest >"${tmp}/rendered.yaml" 2>/dev/null
  yq eval-all 'select(.kind == "Deployment" or .kind == "Service")' "${tmp}/rendered.yaml" >"${tmp}/vap-resources.yaml"
  if kyverno apply policies/vap --resource "${tmp}/vap-resources.yaml" --remove-color >/dev/null 2>&1; then
    echo "❌ :latest wiring sabotage was not caught by the VAP stage" >&2
    exit 1
  fi
  ;;
publish-git)
  PUBLISH_MODE=git PUBLISH_DRY_RUN=true RELEASE_VERSION=v0.1.0 PUBLISH_OUTPUT_DIR="${tmp}/git" bash ./scripts/ci/publish.sh >/dev/null
  [ ! -s "${tmp}/git/diene-xenon-0.1.0.tgz" ] && echo "❌ git chart package missing" >&2 && exit 1
  [ ! -s "${tmp}/git/index.yaml" ] && echo "❌ git chart index missing" >&2 && exit 1
  ;;
publish-oci)
  PUBLISH_MODE=oci PUBLISH_DRY_RUN=true RELEASE_VERSION=v0.1.0 PUBLISH_OUTPUT_DIR="${tmp}/oci" bash ./scripts/ci/publish.sh >/dev/null
  [ ! -s "${tmp}/oci/diene-xenon-0.1.0.tgz" ] && echo "❌ OCI chart package missing" >&2 && exit 1
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
  test -s docs/developer/xenon-baseline.md
  test -s chart/toggle-map.yaml
  test -s chart/templates/lpsm-configmap.yaml
  test -s policies/vap/workload-baseline.yaml
  test -s policies/vap/service-baseline.yaml
  ;;
*)
  echo "❌ unknown validation mode '${mode}'" >&2
  exit 1
  ;;
esac

echo "✅ Xenon ${mode} validation passed"
