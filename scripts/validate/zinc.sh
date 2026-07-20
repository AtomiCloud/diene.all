#!/usr/bin/env bash
# Zinc issuer-set ordinary unit/static testing pyramid (S30/Q-I27).
set -euo pipefail

mode="${1:-}"
release="${RELEASE:-zinc}"
namespace="${NAMESPACE:-sample}"
tmp="$(mktemp -d)"
trap 'rm -rf "${tmp}"' EXIT

[ -z "${mode}" ] && echo "❌ validation mode not set" >&2 && exit 1

case "${mode}" in
schema)
  helm lint chart --namespace "${namespace}" >/dev/null
  for landscape in pichu pikachu raichu amphoros lapras entei; do
    helm lint chart --namespace "${namespace}" --values "chart/values.${landscape}.yaml" >/dev/null
    helm lint chart --namespace "${namespace}" --values "chart/values.${landscape}.yaml" --values chart/values.local.yaml >/dev/null
  done
  ;;

schema-drift)
  bash ./scripts/local/generate-chart-schema.sh "${tmp}/values.schema.json" >/dev/null
  cmp chart/values.schema.json "${tmp}/values.schema.json"
  ;;

lint)
  helm lint chart --namespace "${namespace}"
  for landscape in pichu pikachu raichu amphoros lapras entei; do
    helm lint chart --namespace "${namespace}" --values "chart/values.${landscape}.yaml" --values chart/values.local.yaml
  done
  ;;

render)
  helm template "${release}" chart --namespace "${namespace}" >/dev/null
  for landscape in pichu pikachu raichu amphoros lapras entei; do
    helm template "${release}" chart --namespace "${namespace}" --values "chart/values.${landscape}.yaml" --values chart/values.local.yaml >/dev/null
  done
  ;;

lpsm-labels)
  helm template "${release}" chart --namespace "${namespace}" --values chart/values.pichu.yaml --values chart/values.local.yaml >"${tmp}/default.yaml"
  bash ./scripts/validate/zinc-assert.sh lpsm "${tmp}/default.yaml" atomi.cloud >/dev/null
  helm template "${release}" chart --namespace "${namespace}" --values chart/values.pichu.yaml --values chart/values.local.yaml --set labelPrefix=example.test >"${tmp}/custom.yaml"
  bash ./scripts/validate/zinc-assert.sh lpsm "${tmp}/custom.yaml" example.test >/dev/null
  if yq eval-all -o=json '.' "${tmp}/custom.yaml" | jq -s -e 'map(select(.kind != null)) | any(.[]; .metadata.labels["atomi.cloud/service"] != null)' >/dev/null; then
    echo "❌ labelPrefix override left default-prefixed identity labels" >&2
    exit 1
  fi
  if helm template "${release}" chart --namespace wrong --values chart/values.pichu.yaml >/dev/null 2>&1; then
    echo "❌ render accepted serviceTree.platform != release namespace" >&2
    exit 1
  fi
  ;;

directory-map)
  bash ./scripts/validate/zinc-assert.sh directory-map chart >/dev/null
  mkdir -p "${tmp}/chart"
  cp chart/values.{pichu,pikachu,raichu,amphoros,lapras}.yaml "${tmp}/chart/"
  yq eval -i '.issuer.server = "https://acme-v02.api.letsencrypt.org/directory"' "${tmp}/chart/values.pichu.yaml"
  if bash ./scripts/validate/zinc-assert.sh directory-map "${tmp}/chart" >/dev/null 2>&1; then
    echo "❌ staging-landscape production-directory mutation was not caught" >&2
    exit 1
  fi
  cp chart/values.pichu.yaml "${tmp}/chart/values.pichu.yaml"
  yq eval -i '.issuer.server = "https://acme-staging-v02.api.letsencrypt.org/directory"' "${tmp}/chart/values.pikachu.yaml"
  if bash ./scripts/validate/zinc-assert.sh directory-map "${tmp}/chart" >/dev/null 2>&1; then
    echo "❌ production-landscape staging-directory mutation was not caught" >&2
    exit 1
  fi
  ;;

entei-overlay)
  helm template "${release}" chart --namespace "${namespace}" --values chart/values.entei.yaml --values chart/values.local.yaml >"${tmp}/entei.yaml"
  bash ./scripts/validate/zinc-assert.sh entei-render "${tmp}/entei.yaml" >/dev/null
  helm template "${release}" chart --namespace "${namespace}" --values chart/values.entei.yaml --set entei.staging.server=https://acme-v02.api.letsencrypt.org/directory --set entei.production.server=https://acme-staging-v02.api.letsencrypt.org/directory >"${tmp}/swapped.yaml"
  if bash ./scripts/validate/zinc-assert.sh entei-render "${tmp}/swapped.yaml" >/dev/null 2>&1; then
    echo "❌ ENTEI directory-swap mutation was not caught" >&2
    exit 1
  fi
  helm template "${release}" chart --namespace "${namespace}" --values chart/values.entei.yaml --set-json 'entei.dnsZones=["eevee.dev.atomi.cloud","plusle.dev.atomi.cloud","minun.dev.atomi.cloud"]' >"${tmp}/zone-omitted.yaml"
  if bash ./scripts/validate/zinc-assert.sh entei-render "${tmp}/zone-omitted.yaml" >/dev/null 2>&1; then
    echo "❌ ENTEI hosted-zone omission was not caught" >&2
    exit 1
  fi
  helm template "${release}" chart --namespace "${namespace}" --values chart/values.entei.yaml --set entei.staging.server=https://acme-v02.api.letsencrypt.org/directory >"${tmp}/staging-production.yaml"
  if bash ./scripts/validate/zinc-assert.sh entei-render "${tmp}/staging-production.yaml" >/dev/null 2>&1; then
    echo "❌ ENTEI staging-ref production-directory mutation was not caught" >&2
    exit 1
  fi
  ;;

issuer-cardinality)
  helm template "${release}" chart --namespace "${namespace}" --values chart/values.pichu.yaml >"${tmp}/registered.yaml"
  bash ./scripts/validate/zinc-assert.sh cardinality "${tmp}/registered.yaml" 1 >/dev/null
  helm template "${release}" chart --namespace "${namespace}" --values chart/values.entei.yaml >"${tmp}/entei.yaml"
  bash ./scripts/validate/zinc-assert.sh cardinality "${tmp}/entei.yaml" 2 >/dev/null
  cp -a chart "${tmp}/duplicate-chart"
  cp "${tmp}/duplicate-chart/templates/clusterissuers.yaml" "${tmp}/duplicate-chart/templates/second-issuer-definition.yaml"
  helm template "${release}" "${tmp}/duplicate-chart" --namespace "${namespace}" --values chart/values.pichu.yaml >"${tmp}/duplicate.yaml"
  if bash ./scripts/validate/zinc-assert.sh cardinality "${tmp}/duplicate.yaml" 1 >/dev/null 2>&1; then
    echo "❌ second hand-authored issuer definition was not caught" >&2
    exit 1
  fi
  ;;

no-certificate)
  for landscape in pichu pikachu raichu amphoros lapras entei; do
    helm template "${release}" chart --namespace "${namespace}" --values "chart/values.${landscape}.yaml" >"${tmp}/${landscape}.yaml"
    bash ./scripts/validate/zinc-assert.sh no-certificates "${tmp}/${landscape}.yaml" >/dev/null
  done
  cp "${tmp}/entei.yaml" "${tmp}/wildcard.yaml"
  printf '%s\n' '---' 'apiVersion: cert-manager.io/v1' 'kind: Certificate' 'metadata:' '  name: zinc-wildcard' 'spec:' '  secretName: zinc-wildcardtls' '  dnsNames: ["*.eevee.dev.atomi.cloud"]' >>"${tmp}/wildcard.yaml"
  if bash ./scripts/validate/zinc-assert.sh no-certificates "${tmp}/wildcard.yaml" >/dev/null 2>&1; then
    echo "❌ ENTEI wildcard Certificate fixture was not caught" >&2
    exit 1
  fi
  cp "${tmp}/entei.yaml" "${tmp}/exact.yaml"
  printf '%s\n' '---' 'apiVersion: cert-manager.io/v1' 'kind: Certificate' 'metadata:' '  name: zinc-exact' 'spec:' '  secretName: zinc-exacttls' '  dnsNames: ["api.zinc.nitroso.kirin.eevee.dev.atomi.cloud"]' >>"${tmp}/exact.yaml"
  if bash ./scripts/validate/zinc-assert.sh no-certificates "${tmp}/exact.yaml" >/dev/null 2>&1; then
    echo "❌ chart-authored exact Certificate fixture was not caught" >&2
    exit 1
  fi
  ;;

external-secret)
  helm template "${release}" chart --namespace "${namespace}" --values chart/values.pichu.yaml >"${tmp}/rendered.yaml"
  bash ./scripts/validate/zinc-assert.sh external-secret "${tmp}/rendered.yaml" >/dev/null
  bash ./scripts/validate/zinc-assert.sh no-literal-credentials chart >/dev/null
  # shellcheck disable=SC2016 # The literal rewrite token is the mutation under test.
  yq '(select(.kind == "ExternalSecret") | .spec.dataFrom[0].rewrite[0].regexp.target) = "$1"' "${tmp}/rendered.yaml" >"${tmp}/handwritten-key.yaml"
  if bash ./scripts/validate/zinc-assert.sh external-secret "${tmp}/handwritten-key.yaml" >/dev/null 2>&1; then
    echo "❌ hand-written ExternalSecret key mapping was not caught" >&2
    exit 1
  fi
  cp -a chart "${tmp}/literal-chart"
  printf '%s\n' 'apiToken: fixture-literal-credential' >>"${tmp}/literal-chart/values.yaml"
  if bash ./scripts/validate/zinc-assert.sh no-literal-credentials "${tmp}/literal-chart" >/dev/null 2>&1; then
    echo "❌ inline Cloudflare token fixture was not caught" >&2
    exit 1
  fi
  ;;

rendered-manifests)
  helm template "${release}" chart --namespace "${namespace}" --values chart/values.entei.yaml --values chart/values.local.yaml >"${tmp}/rendered.yaml"
  kubeconform -strict -summary -schema-location default -schema-location 'schemas/{{ .ResourceKind }}.json' "${tmp}/rendered.yaml"
  printf '%s\n' 'apiVersion: v1' 'kind: List' 'items: []' >"${tmp}/vap-resources.yaml"
  kyverno apply policies/vap --resource "${tmp}/vap-resources.yaml" --detailed-results --remove-color >"${tmp}/kyverno.out"
  yq '(select(.kind == "ExternalSecret") | .spec.target) = "schema-invalid"' "${tmp}/rendered.yaml" >"${tmp}/schema-sabotage.yaml"
  if kubeconform -strict -schema-location default -schema-location 'schemas/{{ .ResourceKind }}.json' "${tmp}/schema-sabotage.yaml" >/dev/null 2>&1; then
    echo "❌ rendered-manifest schema sabotage was not caught" >&2
    exit 1
  fi
  ;;

task-surface)
  git status --porcelain=v1 -- chart | sha256sum >"${tmp}/chart-status.before"
  task --silent pichu:local:template >"${tmp}/task-rendered.yaml"
  bash ./scripts/validate/zinc-assert.sh cardinality "${tmp}/task-rendered.yaml" 1 >/dev/null
  git status --porcelain=v1 -- chart | sha256sum >"${tmp}/chart-status.after"
  cmp "${tmp}/chart-status.before" "${tmp}/chart-status.after"
  ;;

k3d-guard)
  bash ./scripts/validate/zinc-assert.sh k3d-script ./scripts/validate/zinc-k3d.sh >/dev/null
  # shellcheck disable=SC2016 # The literal shell expression is the mutation target.
  sed 's/--kube-context "k3d-${cluster_name}" //' ./scripts/validate/zinc-k3d.sh >"${tmp}/unsafe-k3d.sh"
  if bash ./scripts/validate/zinc-assert.sh k3d-script "${tmp}/unsafe-k3d.sh" >/dev/null 2>&1; then
    echo "❌ missing explicit kube-context mutation was not caught" >&2
    exit 1
  fi
  ;;

publish-git)
  PUBLISH_MODE=git PUBLISH_DRY_RUN=true RELEASE_VERSION=v0.1.0 PUBLISH_OUTPUT_DIR="${tmp}/git" bash ./scripts/ci/publish.sh >/dev/null
  test -s "${tmp}/git/diene-zinc-0.1.0.tgz"
  test -s "${tmp}/git/index.yaml"
  ;;

publish-oci)
  PUBLISH_MODE=oci PUBLISH_DRY_RUN=true RELEASE_VERSION=v0.1.0 PUBLISH_OUTPUT_DIR="${tmp}/oci" bash ./scripts/ci/publish.sh >/dev/null
  test -s "${tmp}/oci/diene-zinc-0.1.0.tgz"
  rg -q '^oci://registry.example.invalid/charts$' "${tmp}/oci/oci-ref.txt"
  ;;

version)
  PUBLISH_MODE=git PUBLISH_DRY_RUN=true RELEASE_VERSION=v0.1.0 PUBLISH_OUTPUT_DIR="${tmp}/version" bash ./scripts/ci/publish.sh >/dev/null
  if PUBLISH_MODE=git PUBLISH_DRY_RUN=true RELEASE_VERSION=v0.2.0 PUBLISH_OUTPUT_DIR="${tmp}/mismatch" bash ./scripts/ci/publish.sh >/dev/null 2>&1; then
    echo "❌ chart version/tag mismatch was not caught" >&2
    exit 1
  fi
  ;;

presence)
  test -s docs/developer/zinc-baseline.md
  test -s chart/templates/clusterissuers.yaml
  test -s chart/templates/externalsecret.yaml
  test -s schemas/clusterissuer.json
  test -s schemas/externalsecret.json
  test -x scripts/validate/zinc.sh
  test -x scripts/validate/zinc-assert.sh
  test -x scripts/validate/zinc-k3d.sh
  test ! -e probes
  test ! -e features.json
  ;;

*)
  echo "❌ unknown validation mode '${mode}'" >&2
  exit 1
  ;;
esac

echo "✅ zinc ${mode} validation passed"
