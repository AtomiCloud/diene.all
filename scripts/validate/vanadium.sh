#!/usr/bin/env bash
# ### vanadium-validation
# #### source: vanadium
set -euo pipefail

mode="${1:-}"
release="${RELEASE:-vanadium}"
namespace="${NAMESPACE:-fleet}"
tmp="$(mktemp -d)"
trap 'rm -rf "${tmp}"' EXIT

[ -z "${mode}" ] && echo "❌ validation mode not set" >&2 && exit 1

render() {
  helm template "${release}" chart --namespace "${namespace}" --values chart/values.example.yaml --values chart/values.lapras.yaml
}

# Extract every ValidatingAdmissionPolicy (definitions only; bindings dropped) from
# the rendered chart into individual files under the directory passed in $1. The chart
# is the single source of truth for the policy set; consumers render it and extract
# the definitions the same way for offline kyverno evaluation.
extract_definitions() {
  out_dir="${1}"
  mkdir -p "${out_dir}"
  render >"${tmp}/rendered.yaml"
  mapfile -t names < <(yq eval-all -o=json 'select(.kind == "ValidatingAdmissionPolicy")' "${tmp}/rendered.yaml" | jq -r '.metadata.name')
  for name in "${names[@]}"; do
    yq eval-all "select(.kind == \"ValidatingAdmissionPolicy\" and .metadata.name == \"${name}\")" "${tmp}/rendered.yaml" >"${out_dir}/${name}.yaml"
  done
}

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
  render >"${tmp}/labels.yaml"
  yq eval-all -o=json '.' "${tmp}/labels.yaml" |
    jq -se 'map(select(.kind != null))
      | all(.[]; .metadata.labels["atomi.cloud/platform"] == "fleet"
            and .metadata.labels["atomi.cloud/service"] == "vanadium"
            and .metadata.labels["atomi.cloud/module"] == "admission"
            and .metadata.labels["atomi.cloud/layer"] == "0"
            and .metadata.labels["atomi.cloud/landscape"] == "example"
            and .metadata.labels["atomi.cloud/cluster"] == "lapras"
            and .metadata.annotations["atomi.cloud/platform"] == "fleet")' >/dev/null
  helm template "${release}" chart --namespace "${namespace}" --values chart/values.example.yaml --values chart/values.lapras.yaml --set labelPrefix=example.dev >"${tmp}/override.yaml"
  yq eval-all -o=json '.' "${tmp}/override.yaml" |
    jq -se 'map(select(.kind != null))
      | all(.[]; .metadata.labels["example.dev/platform"] == "fleet"
            and .metadata.annotations["example.dev/service"] == "vanadium"
            and .metadata.labels["atomi.cloud/platform"] == null
            and .metadata.annotations["atomi.cloud/service"] == null)' >/dev/null
  ;;
fullname)
  render >"${tmp}/names.yaml"
  yq eval-all -o=json '.' "${tmp}/names.yaml" |
    jq -se 'map(select(.kind != null) | .metadata.name) | all(.[]; test("^[a-z0-9]+-[a-z0-9]+$"))' >/dev/null
  yq -e '.fullnameOverride | test("^[a-z0-9]+-[a-z0-9]+$")' chart/values.yaml >/dev/null
  ;;
exemption)
  render >"${tmp}/bindings.yaml"
  yq eval-all -o=json '.' "${tmp}/bindings.yaml" |
    jq -se 'map(select(.kind == "ValidatingAdmissionPolicyBinding"))
      | length > 0
      and all(.[]; (.spec.matchResources.namespaceSelector.matchExpressions | length) == 1
                   and .spec.matchResources.namespaceSelector.matchExpressions[0].key == "atomi.cloud/policy-exempt"
                   and .spec.matchResources.namespaceSelector.matchExpressions[0].operator == "NotIn"
                   and (.spec.matchResources.namespaceSelector.matchExpressions[0].values | first) == "true")' >/dev/null
  helm template "${release}" chart --namespace "${namespace}" --values chart/values.example.yaml --set exemption.labelKey=admission-skip >"${tmp}/custom.yaml"
  yq eval-all -o=json '.' "${tmp}/custom.yaml" |
    jq -se 'map(select(.kind == "ValidatingAdmissionPolicyBinding"))
      | all(.[]; .spec.matchResources.namespaceSelector.matchExpressions[0].key == "atomi.cloud/admission-skip")' >/dev/null
  ;;
audit-enforce)
  render >"${tmp}/default.yaml"
  yq eval-all -o=json '.' "${tmp}/default.yaml" |
    jq -se 'map(select(.kind == "ValidatingAdmissionPolicyBinding"))
      | length > 0
      and all(.[]; .spec.validationActions == ["Warn","Audit"]
                   and (.spec.validationActions | index("Deny")) == null)' >/dev/null
  helm template "${release}" chart --namespace "${namespace}" --values chart/values.example.yaml --set 'policies.disallowLatest.actions={Deny}' >"${tmp}/deny.yaml"
  yq eval-all -o=json '.' "${tmp}/deny.yaml" |
    jq -se 'map(select(.kind == "ValidatingAdmissionPolicyBinding" and .metadata.name == "vanadium-disallowlatest"))
      | all(.[]; .spec.validationActions == ["Deny"])' >/dev/null
  invalid_values="${tmp}/invalid-actions.yaml"
  yq '.policies.disallowLatest.actions = ["Deny", "Warn"]' chart/values.example.yaml >"${invalid_values}"
  if helm lint chart --namespace "${namespace}" --values "${invalid_values}" >/dev/null 2>&1; then
    echo "❌ invalid binding action combination passed schema validation" >&2
    exit 1
  fi
  ;;
fixture-schema)
  mapfile -t fixtures < <(rg --files chart/tests/cases chart/tests/init-cases -g '*.yaml' | sort)
  [ "${#fixtures[@]}" -eq 0 ] && echo "❌ no Vanadium fixtures found" >&2 && exit 1
  kubeconform -strict -summary -schema-location default "${fixtures[@]}"
  for fixture in "${fixtures[@]}"; do
    if ! yq -o=json '.' "${fixture}" | jq -e '
      .kind != "Deployment" or
      ((.spec.selector.matchLabels | type) == "object"
       and (.spec.selector.matchLabels | length) > 0
       and .spec.selector.matchLabels == .spec.template.metadata.labels)' >/dev/null; then
      echo "❌ Deployment selector does not exactly match pod-template labels: ${fixture}" >&2
      exit 1
    fi
  done
  selector_negative="${tmp}/selectorless-deployment.yaml"
  selector_negative_log="${tmp}/selectorless-deployment.log"
  yq 'del(.spec.selector)' chart/tests/cases/disallowlatest/bad.yaml >"${selector_negative}"
  if kubeconform -strict -schema-location default "${selector_negative}" >"${selector_negative_log}" 2>&1; then
    echo "❌ selector-less Deployment passed fixture schema validation" >&2
    exit 1
  fi
  if ! rg -q "missing property 'selector'" "${selector_negative_log}"; then
    echo "❌ selector negative failed for an unexpected reason" >&2
    sed 's/^/  /' "${selector_negative_log}" >&2
    exit 1
  fi
  ;;
conformance)
  extract_definitions "${tmp}/defs"
  kubeconform -strict -summary -schema-location default "${tmp}/rendered.yaml"
  [ ! -d chart/tests/cases ] && echo "❌ chart/tests/cases missing" >&2 && exit 1
  for case_dir in chart/tests/cases/*/; do
    token="$(basename "${case_dir}")"
    vap="${tmp}/defs/vanadium-${token}.yaml"
    [ ! -s "${vap}" ] && echo "❌ no VAP definition for case ${token}" >&2 && exit 1
    kyverno apply "${vap}" --resource "${case_dir}good.yaml" --remove-color >/dev/null
    if kyverno apply "${vap}" --resource "${case_dir}bad.yaml" --remove-color >/dev/null 2>&1; then
      echo "❌ negative fixture for ${token} was not caught" >&2 && exit 1
    fi
  done
  for fixture in chart/tests/cases/disallowlatest/good-digest.yaml chart/tests/init-cases/disallowlatest-init/good-digest.yaml; do
    kyverno apply "${tmp}/defs/vanadium-disallowlatest.yaml" --resource "${fixture}" --remove-color >/dev/null
  done
  for fixture in chart/tests/cases/disallowlatest/bad-registry-port.yaml chart/tests/init-cases/disallowlatest-init/bad-registry-port.yaml; do
    if kyverno apply "${tmp}/defs/vanadium-disallowlatest.yaml" --resource "${fixture}" --remove-color >/dev/null 2>&1; then
      echo "❌ registry-port no-tag fixture was not caught: ${fixture}" >&2
      exit 1
    fi
  done
  kyverno apply "${tmp}/defs/vanadium-restrictvolumetypes.yaml" --resource chart/tests/cases/restrictvolumetypes/good-allowed.yaml --remove-color >/dev/null
  if kyverno apply "${tmp}/defs/vanadium-restrictvolumetypes.yaml" --resource chart/tests/cases/restrictvolumetypes/bad-nonhost.yaml --remove-color >/dev/null 2>&1; then
    echo "❌ non-hostPath forbidden-volume fixture was not caught" >&2
    exit 1
  fi
  for init_case in chart/tests/init-cases/*/; do
    token="$(basename "${init_case}")"
    policy="${token%%-init}"
    vap="${tmp}/defs/vanadium-${policy}.yaml"
    [ ! -s "${vap}" ] && echo "❌ no VAP definition for init case ${token}" >&2 && exit 1
    kyverno apply "${vap}" --resource "${init_case}good.yaml" --remove-color >/dev/null
    if kyverno apply "${vap}" --resource "${init_case}bad.yaml" --remove-color >/dev/null 2>&1; then
      echo "❌ init-container negative fixture for ${policy} was not caught" >&2 && exit 1
    fi
  done
  ;;
publish-git)
  PUBLISH_MODE=git PUBLISH_DRY_RUN=true RELEASE_VERSION=v0.1.0 PUBLISH_OUTPUT_DIR="${tmp}/git" bash ./scripts/ci/publish.sh >/dev/null
  chart_name="$(yq -r '.name' chart/Chart.yaml)"
  [ ! -s "${tmp}/git/${chart_name}-0.1.0.tgz" ] && echo "❌ git chart package missing" >&2 && exit 1
  [ ! -s "${tmp}/git/index.yaml" ] && echo "❌ git chart index missing" >&2 && exit 1
  ;;
publish-oci)
  PUBLISH_MODE=oci PUBLISH_DRY_RUN=true RELEASE_VERSION=v0.1.0 PUBLISH_OUTPUT_DIR="${tmp}/oci" bash ./scripts/ci/publish.sh >/dev/null
  chart_name="$(yq -r '.name' chart/Chart.yaml)"
  [ ! -s "${tmp}/oci/${chart_name}-0.1.0.tgz" ] && echo "❌ OCI chart package missing" >&2 && exit 1
  rg -q '^oci://registry.example.invalid/charts$' "${tmp}/oci/oci-ref.txt"
  ;;
version)
  PUBLISH_MODE=git PUBLISH_DRY_RUN=true RELEASE_VERSION=v0.1.0 PUBLISH_OUTPUT_DIR="${tmp}/version" bash ./scripts/ci/publish.sh >/dev/null
  ;;
parity)
  test -s docs/developer/vanadium-baseline.md
  rg -q '^## Sodium to vanadium parity$' docs/developer/vanadium-baseline.md
  rg -q 'NodePort' docs/developer/vanadium-baseline.md
  rg -q 'label-based exemption' docs/developer/vanadium-baseline.md
  ;;
*)
  echo "❌ unknown validation mode '${mode}'" >&2
  exit 1
  ;;
esac

echo "✅ Vanadium ${mode} validation passed"
