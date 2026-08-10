#!/usr/bin/env bash
set -euo pipefail

# cobalt product CI. The helm-wrapper template's sample validate is not inherited
# verbatim: cobalt is a materialized product (S30) with its own ordinary testing
# pyramid. These modes are the unit tier (lint/render/schema/static conformance)
# plus negative fixtures as ordinary tests. The k3d integration tier is reserved
# for orchestration-authorized proof.

mode="${1:-}"
release="${RELEASE:-cobalt}"
namespace="${NAMESPACE:-external-secrets}"
tmp="$(mktemp -d)"
trap 'rm -rf "${tmp}"' EXIT

[ -z "${mode}" ] && echo "❌ validation mode not set" >&2 && exit 1

render() {
  helm template "${release}" chart --namespace "${namespace}" "$@"
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
  render --values chart/values.example.yaml >/dev/null
  render --values chart/values.example.yaml --values chart/values.lapras.yaml >/dev/null
  ;;
store)
  # Positive contract: exactly one v1 ClusterSecretStore, Infisical provider,
  # SoS project, bootstrap-Secret auth reference (no literals), landscape-scoped.
  render --values chart/values.example.yaml >"${tmp}/store.yaml"
  count="$(yq eval-all -o=json '.' "${tmp}/store.yaml" | jq -s 'map(select(.kind == "ClusterSecretStore")) | length')"
  [ "${count}" = "1" ] || {
    echo "❌ expected one ClusterSecretStore, got ${count}" >&2
    exit 1
  }
  yq eval-all -o=json '.' "${tmp}/store.yaml" | jq -s -e '
    map(select(.kind == "ClusterSecretStore"))[0] as $s
    | $s.apiVersion == "external-secrets.io/v1"
      and $s.metadata.name == "cobalt-sos"
      and $s.spec.provider.infisical.hostAPI == "https://secrets.atomi.cloud/api"
      and $s.spec.provider.infisical.secretsScope.projectSlug == "sos"
      and $s.spec.provider.infisical.secretsScope.environmentSlug == "example"
      and $s.spec.provider.infisical.secretsScope.recursive == false
      and $s.spec.provider.infisical.auth.universalAuthCredentials.clientId.name == "cobalt-sos-bootstrap"
      and ($s.spec.provider.infisical.auth.universalAuthCredentials.clientId | has("value") | not)
      and ($s.spec.provider.infisical.auth.universalAuthCredentials.clientSecret | has("value") | not)
      and $s.metadata.annotations["argocd.argoproj.io/sync-wave"] == "-2"' >/dev/null
  ;;
store-credential-negative)
  # Negative fixture: an inline credential literal MUST redden the template.
  if render --values chart/values.example.yaml --set store.infisical.auth.universalAuth.clientId.value=forbidden-literal >/dev/null 2>"${tmp}/err"; then
    echo "❌ inline credential literal was accepted" >&2
    exit 1
  fi
  rg -q 'inline credential literals are forbidden' "${tmp}/err"
  ;;
store-scope-negative)
  # Negative fixture: the store MUST be scoped to a landscape. With no landscape
  # overlay the SoS environment is empty, so rendering MUST fail.
  if helm template "${release}" chart --namespace "${namespace}" >/dev/null 2>"${tmp}/err"; then
    echo "❌ store rendered without a landscape scope" >&2
    exit 1
  fi
  rg -q 'environmentSlug .the cluster landscape. is required' "${tmp}/err"
  ;;
reloader)
  # Upstream ESO 2.7.0 falls back to global.podAnnotations for the controller,
  # webhook, and cert-controller. cobalt opts all three in by default and
  # deliberately opts all three out by setting the same annotation to "false".
  render --values chart/values.example.yaml >"${tmp}/reloader-default.yaml"
  render --values chart/values.example.yaml \
    --set-string 'eso.global.podAnnotations.reloader\.stakater\.com/auto=false' >"${tmp}/reloader-opt-out.yaml"
  for manifest in "${tmp}/reloader-default.yaml:true" "${tmp}/reloader-opt-out.yaml:false"; do
    file="${manifest%:*}"
    expected="${manifest##*:}"
    yq eval-all -o=json '.' "${file}" | jq -s -e --arg expected "${expected}" '
      map(select(.kind == "Deployment"))
      | map(select(.metadata.name == "cobalt-eso"
                   or .metadata.name == "cobalt-eso-webhook"
                   or .metadata.name == "cobalt-eso-cert-controller"))
      | length == 3
        and all(.[]; .spec.template.metadata.annotations["reloader.stakater.com/auto"] == $expected)' >/dev/null
  done
  ;;
authored-v1)
  bash ./scripts/validate/cobalt-authored-v1.sh chart/templates >/dev/null
  ;;
v1beta1-negative)
  # Prove the baseline with the authored-manifest checker, then prove a copied
  # v1beta1 mutation makes that exact checker fail.
  bash ./scripts/validate/cobalt-authored-v1.sh chart/templates >/dev/null
  cp chart/templates/clustersecretstore.yaml "${tmp}/sabotage.yaml"
  sed -i 's#external-secrets.io/v1#external-secrets.io/v1beta1#' "${tmp}/sabotage.yaml"
  if bash ./scripts/validate/cobalt-authored-v1.sh "${tmp}/sabotage.yaml" >"${tmp}/v1-out" 2>"${tmp}/v1-err"; then
    echo "❌ v1beta1 authored-manifest sabotage was not rejected" >&2
    exit 1
  fi
  rg -q 'must use external-secrets.io/v1' "${tmp}/v1-err"
  ;;
crd-lifecycle)
  render --values chart/values.example.yaml >"${tmp}/crds.yaml"
  bash ./scripts/validate/cobalt-crd-lifecycle.sh "${tmp}/crds.yaml" >/dev/null
  ;;
crd-lifecycle-negative)
  # Prove the complete pinned CRD set with the lifecycle checker, then prove
  # disabling those CRDs makes that exact checker fail.
  render --values chart/values.example.yaml >"${tmp}/crds.yaml"
  bash ./scripts/validate/cobalt-crd-lifecycle.sh "${tmp}/crds.yaml" >/dev/null
  render --values chart/values.example.yaml --set eso.installCRDs=false >"${tmp}/crds-disabled.yaml"
  if bash ./scripts/validate/cobalt-crd-lifecycle.sh "${tmp}/crds-disabled.yaml" >"${tmp}/crd-out" 2>"${tmp}/crd-err"; then
    echo "❌ disabled CRD lifecycle sabotage was not rejected" >&2
    exit 1
  fi
  rg -q 'CRD lifecycle set differs' "${tmp}/crd-err"
  ;;
fullname)
  # cobalt-authored names follow <service>-<token> (exactly one dash). The
  # vendored ESO subchart keeps its own upstream naming for its workloads, so
  # only the ClusterSecretStore and the configured fullnameOverride values are
  # asserted here.
  render --values chart/values.example.yaml >"${tmp}/names.yaml"
  yq eval-all -o=json '.' "${tmp}/names.yaml" | jq -s -e '
    map(select(.kind == "ClusterSecretStore") | .metadata.name)
    | length == 1 and all(.[]; test("^[a-z0-9]+-[a-z0-9]+$"))' >/dev/null
  yq -e '.fullnameOverride | test("^[a-z0-9]+-[a-z0-9]+$")' chart/values.yaml >/dev/null
  yq -e '.eso.fullnameOverride | test("^[a-z0-9]+-[a-z0-9]+$")' chart/values.yaml >/dev/null
  ;;
labels)
  render --values chart/values.example.yaml --values chart/values.lapras.yaml >"${tmp}/labels.yaml"
  yq eval-all -o=json '.' "${tmp}/labels.yaml" | jq -s -e '
    map(select(.kind == "ClusterSecretStore"))[0].metadata.labels as $l
    | $l["atomi.cloud/platform"] == "cluster"
      and $l["atomi.cloud/service"] == "cobalt"
      and $l["atomi.cloud/module"] == "sos"
      and $l["atomi.cloud/layer"] == "1"
      and $l["atomi.cloud/landscape"] == "example"
      and $l["atomi.cloud/cluster"] == "lapras"' >/dev/null
  # The single configurable prefix drives every label/annotation helper.
  render --values chart/values.example.yaml --set labelPrefix=example.dev >"${tmp}/override.yaml"
  yq eval-all -o=json '.' "${tmp}/override.yaml" | jq -s -e '
    map(select(.kind == "ClusterSecretStore"))[0].metadata as $m
    | $m.labels["example.dev/service"] == "cobalt"
      and ($m.labels | has("atomi.cloud/service") | not)' >/dev/null
  ;;
rendered-manifests)
  # Inherited Q-G20 stage: helm render -> kubeconform (k8s + local CR schemas)
  # -> kyverno apply VAP eval (definitions only). Upstream ESO CRD definitions
  # are vendored and skip kubeconform (they are validated upstream); cobalt's own
  # ClusterSecretStore is checked against the committed local schema.
  render --values chart/values.example.yaml >"${tmp}/rendered.yaml"
  kubeconform -strict -summary -skip CustomResourceDefinition \
    -schema-location default -schema-location 'schemas/{{ .ResourceKind }}.json' \
    "${tmp}/rendered.yaml"
  yq eval-all 'select(.kind == "Deployment" or .kind == "StatefulSet" or .kind == "DaemonSet" or .kind == "Job" or .kind == "Service")' "${tmp}/rendered.yaml" >"${tmp}/vap-resources.yaml"
  kyverno apply policies/vap --resource "${tmp}/vap-resources.yaml" --detailed-results --remove-color
  ;;
vap-latest-negative)
  # ONE wiring sabotage: an :latest ESO image MUST redden the workload VAP.
  render --values chart/values.example.yaml --set eso.image.tag=latest >"${tmp}/latest.yaml"
  yq eval-all 'select(.kind == "Deployment" or .kind == "StatefulSet" or .kind == "DaemonSet" or .kind == "Job" or .kind == "Service")' "${tmp}/latest.yaml" >"${tmp}/latest-vap.yaml"
  if kyverno apply policies/vap --resource "${tmp}/latest-vap.yaml" --detailed-results --remove-color >/dev/null 2>"${tmp}/vap-err"; then
    echo "❌ :latest image was accepted by the workload VAP" >&2
    exit 1
  fi
  ;;
publish-git)
  PUBLISH_MODE=git PUBLISH_DRY_RUN=true RELEASE_VERSION=v0.1.0 PUBLISH_OUTPUT_DIR="${tmp}/git" bash ./scripts/ci/publish.sh >/dev/null
  [ ! -s "${tmp}/git/diene-cobalt-0.1.0.tgz" ] && echo "❌ git chart package missing" >&2 && exit 1
  [ ! -s "${tmp}/git/index.yaml" ] && echo "❌ git chart index missing" >&2 && exit 1
  ;;
publish-oci)
  PUBLISH_MODE=oci PUBLISH_DRY_RUN=true RELEASE_VERSION=v0.1.0 PUBLISH_OUTPUT_DIR="${tmp}/oci" bash ./scripts/ci/publish.sh >/dev/null
  [ ! -s "${tmp}/oci/diene-cobalt-0.1.0.tgz" ] && echo "❌ OCI chart package missing" >&2 && exit 1
  rg -q '^oci://registry.example.invalid/charts$' "${tmp}/oci/oci-ref.txt"
  ;;
version)
  PUBLISH_MODE=git PUBLISH_DRY_RUN=true RELEASE_VERSION=v0.1.0 PUBLISH_OUTPUT_DIR="${tmp}/version" bash ./scripts/ci/publish.sh >/dev/null
  ;;
presence)
  test -s docs/developer/cobalt-baseline.md
  test -s .claude/skills/cobalt/SKILL.md
  test -s chart/templates/clustersecretstore.yaml
  test -s policies/vap/workload-baseline.yaml
  test -s schemas/clustersecretstore.json
  test -s scripts/validate/cobalt-authored-v1.sh
  test -s scripts/validate/cobalt-crd-lifecycle.sh
  test -s scripts/validate/cobalt-expected-crds.txt
  ;;
*)
  echo "❌ unknown validation mode '${mode}'" >&2
  exit 1
  ;;
esac

echo "✅ Cobalt ${mode} validation passed"
