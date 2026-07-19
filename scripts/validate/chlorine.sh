#!/usr/bin/env bash
# ### chlorine-validate
# #### source: chlorine
#
# Ordinary testing pyramid — unit/static tier (S30/Q-I27). chlorine is a
# materialized chart product, so it carries an ordinary validation script in
# place of the helm-wrapper probe matrix. Positive modes assert the rendered
# chart is conformant; the negative fixtures (vap-latest, schema-violation,
# version-mismatch) prove each gate reddens on sabotage — exactly one caught
# mutation per mechanism.
set -euo pipefail

mode="${1:-}"
release="${RELEASE:-chlorine}"
namespace="${NAMESPACE:-sample}"
tmp="$(mktemp -d)"
trap 'rm -rf "${tmp}"' EXIT

[ -z "${mode}" ] && echo "❌ validation mode not set" >&2 && exit 1

# Full independent landscape + cluster stack used by most modes.
full_values=(--values chart/values.example.yaml --values chart/values.lapras.yaml)

render() {
  helm template "${release}" chart --namespace "${namespace}" "$@" >"${tmp}/rendered.yaml"
}

case "${mode}" in
schema)
  # values.schema.json validates every committed values stack.
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
  helm template "${release}" chart --namespace "${namespace}" "${full_values[@]}" >/dev/null
  ;;
labels)
  # The workload carries the fleet service-tree identity (chlorine owns no
  # workload template; labels are injected through the subchart's tpl hooks).
  render "${full_values[@]}"
  yq eval-all -o=json '.' "${tmp}/rendered.yaml" |
    jq -se 'map(select(.kind == "Deployment"))[0].metadata.labels
      | (.["atomi.cloud/platform"] == "sample")
        and (.["atomi.cloud/service"] == "chlorine")
        and (.["atomi.cloud/module"] == "reloader")
        and (.["atomi.cloud/layer"] == "1")
        and (.["atomi.cloud/landscape"] == "example")
        and (.["atomi.cloud/cluster"] == "lapras")' >/dev/null
  yq eval-all -o=json '.' "${tmp}/rendered.yaml" |
    jq -se 'map(select(.kind == "Deployment"))[0].spec.template.metadata.annotations
      | (.["atomi.cloud/platform"] == "sample")
        and (.["atomi.cloud/instance-original"] == "diene-chlorine:run-001")
        and (.["atomi.cloud/instance-label"] == "diene-chlorine-run-001")' >/dev/null
  # Prefix override: a single configurable labelPrefix flips every key.
  render "${full_values[@]}" --set global.labelPrefix=example.dev
  yq eval-all -o=json '.' "${tmp}/rendered.yaml" |
    jq -se 'map(select(.kind == "Deployment"))[0].metadata.labels
      | (.["example.dev/platform"] == "sample")
        and (.["atomi.cloud/platform"] == null)' >/dev/null
  ;;
reloader)
  # Reloader stays annotation OPT-IN: no auto-reload-all, strategy=annotations.
  render "${full_values[@]}"
  yq eval-all -o=json '.' "${tmp}/rendered.yaml" |
    jq -se 'map(select(.kind == "Deployment"))[0].spec.template.spec.containers[0].args // []
      | (any(. == "--auto-reload-all=true") | not)
        and (any(. == "--reload-strategy=annotations"))' >/dev/null
  ;;
fullname)
  # Exactly-one-dash <service>-<token> on the fullname and the primary workload.
  yq -e '.reloader.fullnameOverride | test("^[a-z0-9]+-[a-z0-9]+$")' chart/values.yaml >/dev/null
  render "${full_values[@]}"
  yq eval-all -o=json '.' "${tmp}/rendered.yaml" |
    jq -se 'map(select(.kind == "Deployment"))[0].metadata.name
      | . == "chlorine-reloader"' >/dev/null
  ;;
rendered-manifests)
  # Inherited rendered-manifest validation stage (Q-G20): template → kubeconform → kyverno VAP eval.
  render "${full_values[@]}"
  kubeconform -strict -summary -schema-location default "${tmp}/rendered.yaml"
  yq eval-all 'select(.kind == "Deployment" or .kind == "StatefulSet" or .kind == "DaemonSet" or .kind == "Job" or .kind == "Service")' "${tmp}/rendered.yaml" >"${tmp}/vap-resources.yaml"
  kyverno apply policies/vap --resource "${tmp}/vap-resources.yaml" --detailed-results --remove-color
  ;;
vap-latest)
  # NEGATIVE fixture: a :latest image must redden the VAP stage (the one wiring sabotage).
  render "${full_values[@]}" --set reloader.image.tag=latest
  yq eval-all 'select(.kind == "Deployment" or .kind == "StatefulSet" or .kind == "DaemonSet" or .kind == "Job")' "${tmp}/rendered.yaml" >"${tmp}/vap-sabotage.yaml"
  if kyverno apply policies/vap --resource "${tmp}/vap-sabotage.yaml" --detailed-results --remove-color >/dev/null 2>&1; then
    echo "❌ :latest image was NOT caught by the VAP stage" >&2
    exit 1
  fi
  ;;
schema-violation)
  # NEGATIVE fixture: a schema-invalid value must redden helm lint.
  if helm lint chart --namespace "${namespace}" --set-string global.serviceTree.service=Invalid-Upper >/dev/null 2>&1; then
    echo "❌ schema-invalid service value was accepted" >&2
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
version-mismatch)
  # NEGATIVE fixture: a version != tag must redden publish (manifest==tag guard).
  if PUBLISH_MODE=git PUBLISH_DRY_RUN=true RELEASE_VERSION=v0.2.0 PUBLISH_OUTPUT_DIR="${tmp}/ver" bash ./scripts/ci/publish.sh >/dev/null 2>&1; then
    echo "❌ version != tag was accepted by the publish guard" >&2
    exit 1
  fi
  ;;
*)
  echo "❌ unknown validation mode '${mode}'" >&2
  exit 1
  ;;
esac

echo "✅ Chlorine ${mode} validation passed"
