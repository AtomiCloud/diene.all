#!/usr/bin/env bash
set -euo pipefail

# Fleet node validation (S30 product — no probe matrix). The diene-platform
# compiler chart inherits helm-wrapper's chart gates (lint/template/schema) as
# ordinary chart CI; the repo-level behaviours (golden render, delivery-mode
# split, Kargo values preservation, registry-CR schema, ArgoCD spike facts) are
# proven here by concrete product tests, not a probe suite. Live SIT/e2e traces
# (throwaway ArgoCD / sandbox repo / k3d) are deferred — see
# docs/domain/fleet-repo.md.

mode="${1:-}"
chart="registry/charts/diene-platform"
fixture="${chart}/tests/fixtures/canary.platform.yaml"
services="platforms/canary/services.yaml"
mercury_fixture="${chart}/tests/fixtures/mercury.platform.yaml"
mercury_services="${chart}/tests/fixtures/mercury.services.yaml"
golden_dir="${chart}/tests/golden"
release="canary"
namespace="canary"
prefix="atomi.cloud"

tmp="$(mktemp -d)"
trap 'rm -rf "${tmp}"' EXIT

[ -z "${mode}" ] && echo "❌ validation mode not set" >&2 && exit 1

fail() {
  echo "❌ $1" >&2
  exit 1
}

# Render the canary platform.
render() {
  helm template "${release}" "${chart}" --namespace "${namespace}" \
    --values "${services}" --values "${fixture}"
}

case "${mode}" in
lint)
  helm lint "${chart}" --namespace "${namespace}" \
    --values "${services}" --values "${fixture}"
  ;;
input-schema)
  helm lint "${chart}" --namespace "${namespace}" \
    --values "${services}" --values "${fixture}" >/dev/null

  cp "${fixture}" "${tmp}/bad-platform.yaml"
  cp "${services}" "${tmp}/bad-services.yaml"
  yq -i '.belt = ["derived-is-not-input"]' "${tmp}/bad-platform.yaml"
  helm lint "${chart}" --namespace "${namespace}" --values "${tmp}/bad-services.yaml" --values "${tmp}/bad-platform.yaml" >/dev/null 2>&1 &&
    fail "combined input schema accepted an unknown root/source-B field"

  cp "${fixture}" "${tmp}/bad-platform.yaml"
  cp "${services}" "${tmp}/bad-services.yaml"
  yq -i 'del(.services[0].repo)' "${tmp}/bad-services.yaml"
  helm lint "${chart}" --namespace "${namespace}" --values "${tmp}/bad-services.yaml" --values "${tmp}/bad-platform.yaml" >/dev/null 2>&1 &&
    fail "combined input schema accepted a malformed source-C roster row"

  cp "${fixture}" "${tmp}/bad-platform.yaml"
  cp "${services}" "${tmp}/bad-services.yaml"
  yq -i '.stages[0] = {"landscape": "pichu", "gate": "sometimes"}' "${tmp}/bad-platform.yaml"
  helm lint "${chart}" --namespace "${namespace}" --values "${tmp}/bad-services.yaml" --values "${tmp}/bad-platform.yaml" >/dev/null 2>&1 &&
    fail "combined input schema accepted a malformed DAG member"

  cp "${fixture}" "${tmp}/bad-platform.yaml"
  yq -i '.dependencies.database.maindb.unexpected = true' "${tmp}/bad-platform.yaml"
  helm lint "${chart}" --namespace "${namespace}" --values "${services}" --values "${tmp}/bad-platform.yaml" >/dev/null 2>&1 &&
    fail "combined input schema accepted an open dependency fragment"

  cp "${fixture}" "${tmp}/bad-platform.yaml"
  yq -i '.dependencies.landscape = "lapras"' "${tmp}/bad-platform.yaml"
  helm lint "${chart}" --namespace "${namespace}" --values "${services}" --values "${tmp}/bad-platform.yaml" >/dev/null 2>&1 &&
    fail "combined input schema accepted a Primordial lapras dependency"

  cp "${fixture}" "${tmp}/bad-platform.yaml"
  yq -i '.virtualLandscapeServices[0].hostname = "forbidden.example"' "${tmp}/bad-platform.yaml"
  helm lint "${chart}" --namespace "${namespace}" --values "${services}" --values "${tmp}/bad-platform.yaml" >/dev/null 2>&1 &&
    fail "combined input schema accepted an open VLS fragment"

  cp "${fixture}" "${tmp}/bad-platform.yaml"
  yq -i '.webhookEngine.engineVersion = "mercury-stable"' "${tmp}/bad-platform.yaml"
  helm lint "${chart}" --namespace "${namespace}" --values "${services}" --values "${tmp}/bad-platform.yaml" >/dev/null 2>&1 &&
    fail "combined input schema accepted a forbidden WebhookEngine field"

  cp "${fixture}" "${tmp}/bad-platform.yaml"
  yq -i '.cloudflareDeploy[0].rollout.steps[0].percent = 101' "${tmp}/bad-platform.yaml"
  helm lint "${chart}" --namespace "${namespace}" --values "${services}" --values "${tmp}/bad-platform.yaml" >/dev/null 2>&1 &&
    fail "combined input schema accepted an invalid deploy rollout"

  cp "${fixture}" "${tmp}/bad-platform.yaml"
  yq -i '.problems[0].entries[0].status = 399' "${tmp}/bad-platform.yaml"
  helm lint "${chart}" --namespace "${namespace}" --values "${services}" --values "${tmp}/bad-platform.yaml" >/dev/null 2>&1 &&
    fail "combined input schema accepted an invalid Problem fragment"
  echo "  closed source-B/source-C schema accepts canary and rejects targeted malformed shapes ✓"
  ;;
schema-drift)
  bash ./scripts/local/generate-platform-schema.sh "${tmp}/values.schema.json" >/dev/null
  cmp "${chart}/values.schema.json" "${tmp}/values.schema.json" ||
    fail "diene-platform values.schema.json is stale — run scripts/local/generate-platform-schema.sh"
  ;;
render)
  render >/dev/null
  # S16: the explicit platform must equal the release namespace, or compile fails.
  helm template "${release}" "${chart}" --namespace "wrong-ns" \
    --values "${services}" --values "${fixture}" >/dev/null 2>&1 &&
    fail "namespace/platform mismatch was accepted (S16 guard broken)"
  echo "  namespace/platform S16 guard rejects a mismatch ✓"
  ;;
row-identity)
  bash ./scripts/validate/fleet-rows.sh platforms >/dev/null
  cp -R platforms "${tmp}/rows"
  row="${tmp}/rows/canary/landscapes/raichu/dummy.yaml"

  yq -i '.platform = "other"' "${row}"
  bash ./scripts/validate/fleet-rows.sh "${tmp}/rows" >/dev/null 2>&1 &&
    fail "row validator accepted a platform mismatch"
  cp platforms/canary/landscapes/raichu/dummy.yaml "${row}"

  yq -i '.service = "other"' "${row}"
  bash ./scripts/validate/fleet-rows.sh "${tmp}/rows" >/dev/null 2>&1 &&
    fail "row validator accepted a service/filename mismatch"
  cp platforms/canary/landscapes/raichu/dummy.yaml "${row}"

  yq -i '.landscape = "other"' "${row}"
  bash ./scripts/validate/fleet-rows.sh "${tmp}/rows" >/dev/null 2>&1 &&
    fail "row validator accepted a landscape/path mismatch"
  echo "  explicit row platform/service/landscape identity + three mismatch negatives ✓"
  ;;
golden)
  render >"${tmp}/prod.yaml"
  cmp "${golden_dir}/canary.prod.yaml" "${tmp}/prod.yaml" ||
    fail "canary prod golden render drifted — regenerate tests/golden/canary.prod.yaml"
  ;;
canary-features)
  render >"${tmp}/r.yaml"
  json() { yq eval-all -o=json '.' "${tmp}/r.yaml" | jq -s "$1"; }
  # Every machinery feature present (asserted present, not just "doesn't error").
  json -e 'map(select(.kind=="Platform")) | length==1' >/dev/null || fail "Platform CR missing"
  json -e 'map(select(.kind=="PlatformDependency")) | length==1' >/dev/null || fail "PlatformDependency missing"
  json -e 'map(select(.kind=="VirtualLandscapeService")) | length==1' >/dev/null || fail "VLS fragment missing"
  json -e 'map(select(.kind=="WebhookEngine")) | length==1' >/dev/null || fail "WebhookEngine missing"
  json -e 'map(select(.kind=="CloudflareDeploy")) | length==1' >/dev/null || fail "CloudflareDeploy missing"
  json -e 'map(select(.kind=="Project")) | length==1' >/dev/null || fail "Kargo Project missing"
  json -e 'map(select(.kind=="Warehouse")) | length==1' >/dev/null || fail "Kargo Warehouse missing"
  # Full registered-fleet serving set present as Kargo Stages; lapras is a
  # secrets-side Landscape anchor and must not materialize centrally.
  json -e '[.[] | select(.kind=="Stage") | .metadata.labels["'"${prefix}"'/landscape"]] | sort == ["amphoros","pichu","pikachu","raichu"]' >/dev/null ||
    fail "Kargo stages do not cover exactly the registered-fleet serving set"
  # ≥1 dependency module per class family.
  json -e 'map(select(.kind=="PlatformDependency"))[0].spec | (.database|length>=1) and (.kv|length>=1) and (.cache|length>=1) and (.store|length>=1)' >/dev/null ||
    fail "PlatformDependency lacks a module in every class family"
  # WebhookEngine post-Q-WH1 shape — NO engine-version field of any kind.
  json -e 'map(select(.kind=="WebhookEngine"))[0].spec | has("version")==false and has("engineVersion")==false and has("engine")==false' >/dev/null ||
    fail "WebhookEngine carries a forbidden engine-version field (Q-WH1)"
  echo "  every platform.yaml feature present + WebhookEngine version-free ✓"
  ;;
dag)
  render >"${tmp}/r.yaml"
  stage() { yq eval-all -o=json '.' "${tmp}/r.yaml" | jq -s '.[] | select(.kind=="Stage" and .metadata.name=="'"$1"'")'; }
  # first step subscribes DIRECTLY to the Warehouse
  stage canary-dummy-pichu | jq -e '.spec.requestedFreight[0].sources.direct==true' >/dev/null ||
    fail "first pipeline step must subscribe direct to the Warehouse"
  # a parallel-set member takes the PRECEDING step as upstream
  stage canary-dummy-pikachu | jq -e '.spec.requestedFreight[0].sources.stages==["canary-dummy-pichu"]' >/dev/null ||
    fail "parallel-set member must take the preceding step as upstream"
  # the step AFTER a parallel set lists ALL of that set's members (rendezvous)
  stage canary-dummy-amphoros | jq -e '.spec.requestedFreight[0].sources.stages | sort == ["canary-dummy-pikachu","canary-dummy-raichu"]' >/dev/null ||
    fail "step after a parallel set must rendezvous on ALL members"
  # object-form step opts into full Kargo semantics (manual gate + soak + verification)
  stage canary-dummy-raichu | jq -e '.metadata.annotations["'"${prefix}"'/promotion-gate"]=="manual" and .metadata.annotations["'"${prefix}"'/soak"]=="1h" and (.spec.verification.analysisTemplates|length>=1)' >/dev/null ||
    fail "object-form pipeline step must carry gate/soak/verification"
  echo "  stages: → Kargo compilation rule (direct / preceding / rendezvous / opt-in gate) ✓"
  ;;
delivery-mode)
  render >"${tmp}/prod.yaml"
  pd() { yq eval-all -o=json '.' "$1" | jq -s '.[] | select(.kind=="PlatformDependency") | .spec'; }
  # replicated (dragonfly) rides the g2 rail on EVERY eligible landscape cluster.
  pd "${tmp}/prod.yaml" | jq -e '.cache | has("hot")' >/dev/null || fail "replicated module must render (prod)"
  # external (neon/upstash/tigris) is declared but fulfilled off-rail from Primordial.
  pd "${tmp}/prod.yaml" | jq -e '(.database|has("maindb")) and (.kv|has("sessions")) and (.store|has("assets"))' >/dev/null ||
    fail "external modules must be declared in prod"
  # A local module must be rejected before Helm can render a Primordial CR.
  cp "${fixture}" "${tmp}/local-platform.yaml"
  yq -i '.dependencies.database.maindb.delivery = "local"' "${tmp}/local-platform.yaml"
  helm template "${release}" "${chart}" --namespace "${namespace}" --values "${services}" --values "${tmp}/local-platform.yaml" >/dev/null 2>&1 &&
    fail "delivery: local was centrally rendered instead of rejected"
  echo "  delivery split: replicated on-rail / external declared / local rejected as Garden-owned ✓"
  ;;
freight-alignment)
  render >"${tmp}/canary.yaml"
  helm template mercury "${chart}" --namespace mercury \
    --values "${mercury_services}" --values "${mercury_fixture}" >"${tmp}/mercury.yaml"
  # Fast deterministic regression over the exact rendered expression. The
  # correction handoff additionally runs these fixtures through Kargo
  # v1.9.10's native freightCreationCriteria evaluator; this Bun helper is not
  # represented as a substitute controller.
  for rendered in "${tmp}/canary.yaml" "${tmp}/mercury.yaml"; do
    while IFS= read -r warehouse; do
      name="$(jq -r '.metadata.namespace + "/" + .metadata.name' <<<"${warehouse}")"
      expression="$(jq -r '.spec.freightCreationCriteria.expression' <<<"${warehouse}")"
      image_repo="$(jq -r '.spec.subscriptions[] | select(.image) | .image.repoURL' <<<"${warehouse}")"
      chart_repo="$(jq -r '.spec.subscriptions[] | select(.chart) | .chart.repoURL' <<<"${warehouse}")"
      expected="imageFrom('${image_repo}').Tag == chartFrom('${chart_repo}').Version"
      [ "${expression}" != "${expected}" ] && fail "${name} has a non-native or wrong freight alignment criterion"
      jq -n --arg image "${image_repo}" --arg chart "${chart_repo}" \
        '{images:[{RepoURL:$image,Tag:"1.2.3"}],charts:[{RepoURL:$chart,Version:"1.2.3"}]}' >"${tmp}/aligned.json"
      bun ./scripts/validate/kargo-freight-criteria.ts "${expression}" "${tmp}/aligned.json" ||
        fail "${name} rejected aligned image/chart freight"
      jq -n --arg image "${image_repo}" --arg chart "${chart_repo}" \
        '{images:[{RepoURL:$image,Tag:"1.2.3"}],charts:[{RepoURL:$chart,Version:"1.2.4"}]}' >"${tmp}/skewed.json"
      if bun ./scripts/validate/kargo-freight-criteria.ts "${expression}" "${tmp}/skewed.json"; then
        fail "${name} accepted mismatched image/chart freight"
      fi
    done < <(yq eval-all -o=json '.' "${rendered}" | jq -c 'select(.kind == "Warehouse")')
  done
  echo "  rendered Kargo criterion accepts aligned fixtures and rejects skew, including mercury/webhook ✓"
  ;;
kargo-values-preservation)
  render >"${tmp}/r.yaml"
  # The fixed git-update promotion template bumps ONLY pin.tag; it must never
  # touch the human values: override block (Kargo preserves it byte-for-byte).
  yq eval-all -o=json '.' "${tmp}/r.yaml" |
    jq -s '.[] | select(.kind=="Stage") | .spec.promotionTemplate.spec.steps[] | select(.uses=="yaml-update") | .config.updates' |
    jq -e 'length==1 and .[0].key=="pin.tag"' >/dev/null ||
    fail "Kargo yaml-update must touch ONLY pin.tag (values: block preserved)"
  # The canary raichu row carries a human values: block; assert it exists and is
  # covered by the persistence-meta convention.
  yq -e '.values.workload.replicas==3 and (.valuesMeta.addedAt|length>0)' \
    platforms/canary/landscapes/raichu/dummy.yaml >/dev/null ||
    fail "canary raichu row values: override or valuesMeta missing"
  echo "  Kargo promotion touches only the pin; values: override preserved ✓"
  ;;
row-values-persistence)
  # >7d persistence guardrail (unit, injected clock). A values: block present in
  # a row for more than 7 days without being folded back into the chart trips a
  # finding. NOW is injectable so CI is deterministic.
  now="${FLEET_NOW:-2026-07-19T00:00:00Z}"
  now_s="$(date -u -d "${now}" +%s)"
  findings=0
  while IFS= read -r row; do
    added="$(yq -r '.valuesMeta.addedAt // ""' "${row}")"
    has_values="$(yq -r 'has("values")' "${row}")"
    [ "${has_values}" != "true" ] && continue
    [ -z "${added}" ] && fail "row ${row} has values: but no valuesMeta.addedAt"
    added_s="$(date -u -d "${added}" +%s)"
    age_days=$(((now_s - added_s) / 86400))
    if [ "${age_days}" -gt 7 ]; then
      echo "  ⚠ persistence finding: ${row} values: block is ${age_days}d old (>7d, fold back into the chart)"
      findings=$((findings + 1))
    else
      echo "  ${row} values: block is ${age_days}d old (≤7d, within the ops-knob window) ✓"
    fi
  done < <(find platforms -type f -name '*.yaml' -path '*/landscapes/*')
  # Positive gate: with the committed clock the canary block is fresh (no finding).
  [ "${findings}" -ne 0 ] && fail "un-folded >7d values: overrides present (see findings above)"
  # Negative proof: a clock 8+ days later MUST produce a finding.
  late="$(FLEET_NOW=2026-08-01T00:00:00Z bash "$0" row-values-persistence 2>&1 || true)"
  echo "${late}" | grep -q 'persistence finding' ||
    fail "persistence guardrail failed to fire on an aged (>7d) override"
  echo "  row values: >7d persistence guardrail proven (fresh passes, aged fires) ✓"
  ;;
registry-cr)
  # Registry topology CRs validate against the frozen T3 CRD schemas; a
  # schema-invalid manifest turns this red. ArgoCD Application/ApplicationSet
  # are upstream kinds (skipped — no diene schema).
  kubeconform -strict -summary \
    -schema-location default \
    -schema-location 'schemas/{{ .ResourceKind }}.json' \
    -skip Application,ApplicationSet \
    registry/landscapes registry/clusters registry/virtual-landscapes \
    registry/fleet-root.yaml registry/platforms-appset.yaml
  yq -e '.kind == "Landscape" and .metadata.name == "lapras"' registry/landscapes/lapras.yaml >/dev/null ||
    fail "lapras secrets-side Landscape anchor is missing"
  while IFS= read -r cluster; do
    [ "$(yq -r '.spec.landscape // ""' "${cluster}")" = "lapras" ] &&
      fail "lapras ClusterRegistration is forbidden by WAL Q-L9: ${cluster}"
  done < <(find registry/clusters -type f -name '*.yaml' | sort)
  ;;
rendered-cr)
  # The compiler chart's own diene CRD kinds validate against the frozen
  # schemas. Upstream ArgoCD/Kargo Project/Stage kinds are skipped. Warehouse
  # uses the pinned Kargo v1.9.10 validation slice; CloudflareDeploy including
  # optional rollout validates against the frozen T3 shape.
  render >"${tmp}/r.yaml"
  kubeconform -strict -summary \
    -schema-location default \
    -schema-location 'schemas/{{ .ResourceKind }}.json' \
    -skip Application,ApplicationSet,Project,Stage \
    "${tmp}/r.yaml"
  ;;
cloudflare-rollout-negative)
  render >"${tmp}/r.yaml"
  yq eval-all 'select(.kind == "CloudflareDeploy")' "${tmp}/r.yaml" >"${tmp}/cloudflaredeploy.yaml"
  kubeconform -strict -summary -schema-location 'schemas/{{ .ResourceKind }}.json' "${tmp}/cloudflaredeploy.yaml" >/dev/null
  yq -i '.spec.rollout.steps[0].percent = 101' "${tmp}/cloudflaredeploy.yaml"
  if kubeconform -strict -summary -schema-location 'schemas/{{ .ResourceKind }}.json' "${tmp}/cloudflaredeploy.yaml" >/dev/null 2>&1; then
    fail "CloudflareDeploy accepted an invalid rollout percentage"
  fi
  echo "  frozen CloudflareDeploy rollout schema accepts canary and rejects invalid rollout ✓"
  ;;
webhookengine-version-negative)
  # A WebhookEngine fixture declaring an engine-version field must be
  # schema-invalid (Q-WH1: no per-platform version; the CF-era
  # desiredVersionFrom:{tag: mercury-stable} render is DEAD).
  cat >"${tmp}/bad-webhookengine.yaml" <<'YAML'
apiVersion: fleet.atomi.cloud/v1alpha1
kind: WebhookEngine
metadata:
  name: mercury
spec:
  home:
    vlandscape: mew
  engineVersion: mercury-stable
YAML
  if kubeconform -strict -summary \
    -schema-location default \
    -schema-location 'schemas/{{ .ResourceKind }}.json' \
    "${tmp}/bad-webhookengine.yaml" >/dev/null 2>&1; then
    fail "WebhookEngine with an engine-version field was ACCEPTED (Q-WH1 guard broken)"
  fi
  echo "  WebhookEngine engine-version field is schema-rejected ✓"
  ;;
appset-scope)
  render >"${tmp}/r.yaml"
  as() { yq eval-all -o=json '.' "${tmp}/r.yaml" | jq -s '.[] | select(.kind=="ApplicationSet")'; }
  # ArgoCD spike facts encoded as config, not just docs.
  # matrix generator (git-files × cluster label selector).
  as | jq -e '.spec.generators | any(.[]; has("matrix"))' >/dev/null ||
    fail "AppSet must carry the matrix (git-files × clusters) generator"
  # Generated names, OCI paths, selectors, and destinations consume explicit
  # row fields. path-derived values appear only in templatePatch validation.
  as | jq -e '.spec.generators[0].git.template.metadata.name == "{{ .platform }}-{{ .landscape }}-{{ .service }}-primordial"' >/dev/null ||
    fail "g1 name must consume explicit row fields"
  as | jq -e '.spec.generators[0].git.template.spec.sources[0].repoURL == "oci://registry.atomi.cloud/{{ .platform }}-{{ .service }}-primordial"' >/dev/null ||
    fail "g1 OCI path must consume explicit row fields"
  as | jq -e '.spec.generators[0].git.template.spec.destination.namespace == "{{ .platform }}"' >/dev/null ||
    fail "g1 destination namespace must consume explicit row platform"
  as | jq -e '.spec.generators[1].matrix.template.metadata.name == "{{ .platform }}-{{ .landscape }}-{{ .service }}-{{ .name }}"' >/dev/null ||
    fail "g2 name must consume explicit row fields"
  as | jq -e '.spec.generators[1].matrix.generators[1].clusters.selector.matchLabels["'"${prefix}"'/landscape"] == "{{ .landscape }}"' >/dev/null ||
    fail "g2 selector must consume explicit row landscape"
  as | jq -e '.spec.generators[1].matrix.template.spec.sources[0].repoURL == "oci://registry.atomi.cloud/{{ .platform }}-{{ .service }}"' >/dev/null ||
    fail "g2 OCI path must consume explicit row fields"
  as | jq -e '.spec.templatePatch | contains("ne .platform \"canary\"") and contains("has .service") and contains("ne .service $filenameService") and contains("ne .landscape $pathLandscape")' >/dev/null ||
    fail "AppSet templatePatch must validate row fields against roster/path/filename"
  as | jq -e '[.. | strings | select(test("path\\.segments|path\\.filename"))] | length == 1' >/dev/null ||
    fail "path-derived identity leaked outside the row-validation templatePatch"
  echo "  AppSet g1/g2 uses explicit row identity with fail-before-render path/roster guards ✓"
  ;;
platforms-appset)
  # The committed platforms AppSet: SCM-provider generator over *.carbon,
  # three-source Application, machinery-stable pin with canary-on-main split,
  # canary auto-sync disabled via templatePatch.
  f=registry/platforms-appset.yaml
  yq -e '.spec.generators[0].scmProvider.github.organization=="AtomiCloud"' "${f}" >/dev/null ||
    fail "platforms AppSet must use an SCM-provider generator over the AtomiCloud org"
  yq -e '.spec.generators[0].scmProvider.filters[0].repositoryMatch=="\\.carbon$"' "${f}" >/dev/null ||
    fail "platforms AppSet must filter to *.carbon repos"
  yq -e '[.spec.template.spec.sources[] | .ref] | contains(["carbon","services"])' "${f}" >/dev/null ||
    fail "platforms AppSet must declare three sources (chart + carbon + services refs)"
  yq -e '.spec.template.spec.sources[0].targetRevision | test("canary.carbon.*main.*machinery-stable")' "${f}" >/dev/null ||
    fail "platforms AppSet source A must pin machinery-stable with the canary-on-main split"
  patch="$(yq -r '.spec.templatePatch' "${f}")"
  { echo "${patch}" | grep -q 'ne .repository "canary.carbon"' && echo "${patch}" | grep -q 'automated'; } ||
    fail "platforms AppSet must disable auto-sync for canary via templatePatch"
  echo "  platforms AppSet: scmProvider *.carbon + 3-source + machinery-stable/main split + canary manual-sync ✓"
  ;;
guard)
  bash ./scripts/validate/registry-guard.sh
  ;;
presence)
  test -s docs/domain/fleet-repo.md || fail "docs/domain/fleet-repo.md missing"
  test -s .github/CODEOWNERS || fail "CODEOWNERS missing"
  test -s .github/rulesets/registry-guard-main.json || fail "registry ruleset payload missing"
  test -s scripts/local/registry-guard-apply.sh || fail "registry-guard apply script missing"
  test -s "${chart}/values.schema.json" || fail "compiler chart values.schema.json missing"
  test -s "${chart}/values.schema.source.json" || fail "deliberate compiler schema source missing"
  test -s "${golden_dir}/canary.prod.yaml" || fail "prod golden render missing"
  # pin-management + webhook-wiring docs are published in the domain doc.
  rg -q '^## The `machinery-stable` tag' docs/domain/fleet-repo.md || fail "machinery-stable pin doc missing"
  rg -q '^## The `mercury-stable` pin' docs/domain/fleet-repo.md || fail "mercury-stable pin doc missing"
  rg -q 'webhook' docs/domain/fleet-repo.md || fail "ArgoCD webhook wiring doc missing"
  ;;
*)
  echo "❌ unknown validation mode '${mode}'" >&2
  exit 1
  ;;
esac

echo "✅ fleet ${mode} validation passed"
