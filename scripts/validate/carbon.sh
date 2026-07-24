#!/usr/bin/env bash
set -euo pipefail

mode="${1:-}"
tmp="$(mktemp -d)"
trap 'rm -rf "${tmp}"' EXIT

[ -n "${mode}" ] || {
  echo "❌ Carbon validation mode is required" >&2
  exit 1
}
case "${mode}" in
schema | schema-drift | lint | render | render-contract | namespace-negative | dependency-missing-negative | dependency-conflict-negative | folder-mapping-negative | garden | garden-store-negative | labels | rendered-manifests | vap-wiring-negative | cyan-offline | platform-schema | scaffold | scaffold-offline | workflow-source | workflow-filter | workflow-name | workflow-concurrency | static | publish-git | publish-oci | presence)
  ;;
*)
  echo "❌ unknown Carbon validation mode '${mode}'" >&2
  exit 1
  ;;
esac

render_app() {
  helm template carbon chart --namespace diene "$@"
}

render_primordial() {
  helm template carbon-primordial primordial-chart --namespace diene "$@"
}

case "${mode}" in
schema)
  helm lint chart >/dev/null
  helm lint chart --values chart/values.example.yaml >/dev/null
  helm lint chart --values chart/values.example.yaml --values chart/values.lapras.yaml >/dev/null
  helm lint primordial-chart >/dev/null
  helm lint primordial-chart --values primordial-chart/values.example.yaml >/dev/null
  helm lint primordial-chart --values primordial-chart/values.example.yaml --values primordial-chart/values.lapras.yaml >/dev/null
  ;;
schema-drift)
  bash scripts/local/generate-chart-schema.sh chart "${tmp}/app.schema.json" >/dev/null
  bash scripts/local/generate-chart-schema.sh primordial-chart "${tmp}/primordial.schema.json" >/dev/null
  cmp chart/values.schema.json "${tmp}/app.schema.json"
  cmp primordial-chart/values.schema.json "${tmp}/primordial.schema.json"
  bash scripts/local/generate-platform-schema.sh "${tmp}/platform.schema.json" >/dev/null
  cmp platform.schema.json "${tmp}/platform.schema.json"
  ;;
lint)
  helm lint chart
  helm lint chart --values chart/values.example.yaml
  helm lint chart --values chart/values.example.yaml --values chart/values.lapras.yaml
  helm lint primordial-chart
  helm lint primordial-chart --values primordial-chart/values.example.yaml
  helm lint primordial-chart --values primordial-chart/values.example.yaml --values primordial-chart/values.lapras.yaml
  ;;
render)
  render_app >/dev/null
  render_app --values chart/values.example.yaml >/dev/null
  render_app --values chart/values.example.yaml --values chart/values.lapras.yaml >/dev/null
  render_primordial >/dev/null
  render_primordial --values primordial-chart/values.example.yaml >/dev/null
  render_primordial --values primordial-chart/values.example.yaml --values primordial-chart/values.lapras.yaml >/dev/null
  ;;
render-contract)
  render_app --values chart/values.example.yaml >"${tmp}/app.yaml"
  render_primordial --values primordial-chart/values.example.yaml >"${tmp}/primordial.yaml"
  bash scripts/validate/carbon-render-contract.sh "${tmp}/app.yaml" "${tmp}/primordial.yaml" diene diene 1 >/dev/null
  ;;
namespace-negative)
  render_app --values chart/values.example.yaml >"${tmp}/app.yaml"
  render_primordial --values primordial-chart/values.example.yaml >"${tmp}/primordial.yaml"
  yq eval-all '(. | select(.kind == "Namespace") | .metadata.name) = "hardcoded"' "${tmp}/app.yaml" >"${tmp}/bad-app.yaml"
  if bash scripts/validate/carbon-render-contract.sh "${tmp}/bad-app.yaml" "${tmp}/primordial.yaml" diene diene 1 >/dev/null 2>&1; then
    echo "❌ hard-coded namespace fixture was accepted" >&2
    exit 1
  fi
  ;;
dependency-missing-negative)
  render_app --values chart/values.example.yaml >"${tmp}/app.yaml"
  render_primordial --values primordial-chart/values.example.yaml >"${tmp}/primordial.yaml"
  yq eval-all 'select(.kind != "PlatformDependency")' "${tmp}/primordial.yaml" >"${tmp}/missing.yaml"
  printf '%s\n' '---' >"${tmp}/empty.yaml"
  if bash scripts/validate/carbon-render-contract.sh "${tmp}/app.yaml" "${tmp}/empty.yaml" diene diene 1 >/dev/null 2>&1; then
    echo "❌ missing PlatformDependency fixture was accepted" >&2
    exit 1
  fi
  ;;
dependency-conflict-negative)
  if render_primordial --values tests/fixtures/primordial-duplicate.yaml >/dev/null 2>"${tmp}/err"; then
    echo "❌ duplicate PlatformDependency writer was accepted" >&2
    exit 1
  fi
  rg -q 'Conflict: duplicate PlatformDependency writer' "${tmp}/err"
  ;;
folder-mapping-negative)
  render_app --values chart/values.example.yaml >"${tmp}/app.yaml"
  render_primordial --values primordial-chart/values.example.yaml >"${tmp}/primordial.yaml"
  yq eval-all '(. | select(.kind == "ExternalSecret") | .spec) |= (del(.dataFrom) | .data = [{"secretKey":"clientId","remoteRef":{"key":"clientId"}}])' "${tmp}/app.yaml" >"${tmp}/bad-app.yaml"
  if bash scripts/validate/carbon-render-contract.sh "${tmp}/bad-app.yaml" "${tmp}/primordial.yaml" diene diene 1 >/dev/null 2>&1; then
    echo "❌ hand-written ExternalSecret mapping fixture was accepted" >&2
    exit 1
  fi
  ;;
garden)
  render_app --values chart/values.example.yaml --values chart/values.lapras.yaml >"${tmp}/app.yaml"
  render_primordial --values primordial-chart/values.example.yaml --values primordial-chart/values.lapras.yaml >"${tmp}/primordial.yaml"
  bash scripts/validate/carbon-render-contract.sh "${tmp}/app.yaml" "${tmp}/primordial.yaml" feature-carbon-123 diene 1 >/dev/null
  ;;
garden-store-negative)
  render_app --values chart/values.example.yaml --values chart/values.lapras.yaml >"${tmp}/app.yaml"
  render_primordial --values primordial-chart/values.example.yaml >"${tmp}/primordial.yaml"
  yq eval-all 'select(.kind != "SecretStore")' "${tmp}/app.yaml" >"${tmp}/missing-store.yaml"
  if bash scripts/validate/carbon-render-contract.sh "${tmp}/missing-store.yaml" "${tmp}/primordial.yaml" feature-carbon-123 diene 1 >/dev/null 2>&1; then
    echo "❌ Garden render without its branch SecretStore was accepted" >&2
    exit 1
  fi
  ;;
labels)
  render_app --set labelPrefix=example.dev >"${tmp}/app.yaml"
  render_primordial --values primordial-chart/values.example.yaml --set labelPrefix=example.dev >"${tmp}/primordial.yaml"
  yq eval-all -o=json '.' "${tmp}/app.yaml" "${tmp}/primordial.yaml" | jq -s -e '
    map(select(. != null)) | all(.[];
      .metadata.labels["example.dev/service"] == "carbon" and
      (.metadata.labels | has("atomi.cloud/service") | not))' >/dev/null
  ;;
rendered-manifests)
  render_app --values chart/values.example.yaml >"${tmp}/app.yaml"
  render_primordial --values primordial-chart/values.example.yaml >"${tmp}/primordial.yaml"
  kubeconform -strict -summary \
    -schema-location 'schemas/{{ .ResourceKind }}.json' \
    "${tmp}/app.yaml" "${tmp}/primordial.yaml"
  kyverno apply policies/vap --resource tests/fixtures/vap-pass.yaml --detailed-results --remove-color
  ;;
vap-wiring-negative)
  if kyverno apply policies/vap --resource tests/fixtures/vap-latest.yaml --detailed-results --remove-color >/dev/null 2>"${tmp}/err"; then
    echo "❌ Carbon Q-G20 :latest wiring fixture was accepted" >&2
    exit 1
  fi
  ;;
cyan-offline)
  bun build cyan/index.ts \
    --external @atomicloud/cyan-sdk \
    --target bun \
    --outfile "${tmp}/cyan.js" >/dev/null

  cp cyan/index.ts "${tmp}/cyan-invalid.ts"
  printf '\nconst carbonSyntaxFault: = ;\n' >>"${tmp}/cyan-invalid.ts"
  if bun build "${tmp}/cyan-invalid.ts" \
    --external @atomicloud/cyan-sdk \
    --target bun \
    --outfile "${tmp}/cyan-invalid.js" >"${tmp}/cyan-invalid.out" 2>"${tmp}/cyan-invalid.err"; then
    echo "❌ malformed Cyan TypeScript was accepted by the offline parser" >&2
    exit 1
  fi
  rg -q 'error:' "${tmp}/cyan-invalid.err"

  rg -Fxq '[ "${offline}" = "--offline" ] || bun install --cwd cyan --frozen-lockfile' scripts/ci/carbon.sh
  rg -Fxq 'bash scripts/validate/carbon.sh cyan-offline' scripts/ci/carbon.sh
  rg -Fxq '  bash scripts/validate/carbon.sh scaffold' scripts/ci/carbon.sh
  rg -Fxq '  (cd cyan && bun x tsc --noEmit)' scripts/validate/carbon.sh
  yq -e '
    .jobs.validate.steps[] |
    select(.name == "Run Carbon validation") |
    .run == "nix develop .#ci -c ./scripts/ci/carbon.sh"
  ' .github/workflows/⚡reusable-carbon.yaml >/dev/null
  ;;
platform-schema)
  bun cyan/validate-platform-schema.ts platform.schema.json platform.yaml
  if bun cyan/validate-platform-schema.ts platform.schema.json tests/fixtures/platform-invalid.yaml >/dev/null 2>&1; then
    echo "❌ invalid one-member parallel stage was accepted" >&2
    exit 1
  fi
  ;;
scaffold)
  (cd cyan && bun x tsc --noEmit)
  ;;
scaffold-offline)
  jq -e . platform.schema.source.json platform.schema.json >/dev/null
  ;;
esac

case "${mode}" in
scaffold | scaffold-offline)
  [ "$(rg -c 'await i[.]text' cyan/index.ts)" = "1" ] || {
    echo "❌ scaffold must ask exactly one text question" >&2
    exit 1
  }
  if rg -q 'i[.](select|confirm)|IDeterminism|registry query|landscape (list|override)' cyan/index.ts; then
    echo "❌ scaffold contains a forbidden question or discovery mechanism" >&2
    exit 1
  fi
  yq -o=json platform.yaml | jq -e '
    (keys == ["landscapes", "stages"]) and
    .landscapes == ["pichu","pikachu","raichu","amphoros"] and
    .stages == ["pichu","pikachu",["raichu","amphoros"]]' >/dev/null
  scaffold_dir="$(mktemp -d .carbon-scaffold.XXXXXX)"
  bash scripts/local/generate-carbon-scaffold.sh "${scaffold_dir}" >/dev/null
  diff -ru templates/base "${scaffold_dir}"
  find "${scaffold_dir}" -mindepth 1 -delete
  rmdir "${scaffold_dir}"
  ;;
esac

case "${mode}" in
workflow-source)
  bash scripts/validate/release-source.sh >/dev/null
  if RELEASE_WORKFLOW=tests/fixtures/workflows/release-source.yaml bash scripts/validate/release-source.sh >/dev/null 2>&1; then
    echo "❌ release source fixture was accepted" >&2
    exit 1
  fi
  ;;
workflow-filter)
  bash scripts/validate/release-filter.sh >/dev/null
  if RELEASE_WORKFLOW=tests/fixtures/workflows/release-filter.yaml bash scripts/validate/release-filter.sh >/dev/null 2>&1; then
    echo "❌ release filter fixture was accepted" >&2
    exit 1
  fi
  ;;
workflow-name)
  bash scripts/validate/workflow-names.sh >/dev/null
  if CI_WORKFLOW=tests/fixtures/workflows/ci-name.yaml bash scripts/validate/workflow-names.sh >/dev/null 2>&1; then
    echo "❌ workflow name fixture was accepted" >&2
    exit 1
  fi
  ;;
workflow-concurrency)
  bash scripts/validate/release-concurrency.sh >/dev/null
  if RELEASE_WORKFLOW=tests/fixtures/workflows/release-concurrency.yaml bash scripts/validate/release-concurrency.sh >/dev/null 2>&1; then
    echo "❌ release concurrency fixture was accepted" >&2
    exit 1
  fi
  ;;
static)
  test ! -d probes
  test ! -e features.json
  if rg -n -i 'kind:[[:space:]]*(Application|ApplicationSet|PushSecret)|sulfoxide-bromine|vcluster|latest|update' chart/templates primordial-chart/templates platform.yaml; then
    echo "❌ forbidden Carbon surface found" >&2
    exit 1
  fi
  if rg -n -i --glob '!**/node_modules/**' 'image:|Dockerfile|per-service.*pin|dependency.*bundle|bump chain' chart primordial-chart platform.yaml cyan templates/base; then
    echo "❌ container or per-service dependency surface found" >&2
    exit 1
  fi
  [ "$(find chart/templates -maxdepth 1 -type f | wc -l)" -eq 4 ]
  [ "$(find primordial-chart/templates -maxdepth 1 -type f | wc -l)" -eq 2 ]
  ;;
publish-git)
  PUBLISH_MODE=git PUBLISH_DRY_RUN=true RELEASE_VERSION=v0.1.0 PUBLISH_OUTPUT_DIR="${tmp}/git" bash scripts/ci/publish.sh >/dev/null
  test -s "${tmp}/git/diene-carbon-0.1.0.tgz"
  test -s "${tmp}/git/diene-carbon-primordial-0.1.0.tgz"
  test -s "${tmp}/git/index.yaml"
  ;;
publish-oci)
  PUBLISH_MODE=oci PUBLISH_DRY_RUN=true RELEASE_VERSION=v0.1.0 PUBLISH_OUTPUT_DIR="${tmp}/oci" bash scripts/ci/publish.sh >/dev/null
  test -s "${tmp}/oci/diene-carbon-0.1.0.tgz"
  test -s "${tmp}/oci/diene-carbon-primordial-0.1.0.tgz"
  rg -q '^oci://registry.example.invalid/charts$' "${tmp}/oci/oci-ref.txt"
  ;;
presence)
  test -s docs/developer/carbon-baseline.md
  test -s chart/templates/namespace.yaml
  test -s chart/templates/token-externalsecret.yaml
  test -s chart/templates/secretstore.yaml
  test -s primordial-chart/templates/platformdependencies.yaml
  test -s platform.yaml
  test -s platform.schema.json
  test -s cyan/index.ts
  test -s scripts/validate/carbon-k3d.sh
  ;;
esac

echo "✅ Carbon ${mode} validation passed"
