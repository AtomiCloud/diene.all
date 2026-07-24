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
  echo "  Kargo promotion template config is pin-only; values: fixture is present ✓"
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
  # Registry CRs validate against frozen fleet-owned slices. Application and
  # ApplicationSet use hand-reduced, pinned Argo CD v3.4.5 schemas.
  kubeconform -strict -summary \
    -schema-location default \
    -schema-location 'schemas/{{ .ResourceKind }}.json' \
    registry/landscapes registry/clusters registry/virtual-landscapes \
    registry/fleet-root.yaml registry/argocd-webhook-secret.yaml \
    registry/platforms-appset.yaml

  # Deterministic negative: Applications may not declare an empty source URL.
  cp registry/fleet-root.yaml "${tmp}/invalid-application.yaml"
  yq -i '.spec.source.repoURL = ""' "${tmp}/invalid-application.yaml"
  if kubeconform -strict -summary \
    -schema-location default \
    -schema-location 'schemas/{{ .ResourceKind }}.json' \
    "${tmp}/invalid-application.yaml" >/dev/null 2>&1; then
    fail "Application schema accepted an empty source repoURL"
  fi
  yq -e '.kind == "Landscape" and .metadata.name == "lapras"' registry/landscapes/lapras.yaml >/dev/null ||
    fail "lapras secrets-side Landscape anchor is missing"
  while IFS= read -r cluster; do
    [ "$(yq -r '.spec.landscape // ""' "${cluster}")" = "lapras" ] &&
      fail "lapras ClusterRegistration is forbidden by WAL Q-L9: ${cluster}"
  done < <(find registry/clusters -type f -name '*.yaml' | sort)
  echo "  registry CRs validate against frozen schemas; invalid Application source is rejected ✓"
  ;;
webhook-secret)
  # Build-time semantic contract for the authenticated GitHub -> ArgoCD
  # refresh path. The secret value never enters git: ESO merges exactly the
  # Infisical-backed webhook.github.secret key into the existing argocd-secret.
  webhook_contract() {
    yq -e '
      .apiVersion == "external-secrets.io/v1" and
      .kind == "ExternalSecret" and
      .metadata.namespace == "argocd" and
      .spec.secretStoreRef.kind == "ClusterSecretStore" and
      .spec.secretStoreRef.name == "infisical" and
      .spec.target.name == "argocd-secret" and
      .spec.target.creationPolicy == "Merge" and
      .spec.target.deletionPolicy == "Retain" and
      (.spec.data | length) == 1 and
      .spec.data[0].secretKey == "webhook.github.secret" and
      .spec.data[0].remoteRef.key == "/argocd/webhook/webhook.github.secret" and
      (.spec | has("dataFrom") | not)
    ' "$1" >/dev/null 2>&1
  }

  webhook=registry/argocd-webhook-secret.yaml
  kubeconform -strict -summary \
    -schema-location default \
    -schema-location 'schemas/{{ .ResourceKind }}.json' \
    "${webhook}" >/dev/null
  webhook_contract "${webhook}" ||
    fail "ArgoCD webhook ExternalSecret is not the exact Infisical -> argocd-secret merge contract"

  cp "${webhook}" "${tmp}/wrong-key.yaml"
  yq -i '.spec.data[0].secretKey = "webhook.github.wrong"' "${tmp}/wrong-key.yaml"
  if webhook_contract "${tmp}/wrong-key.yaml"; then
    fail "webhook contract accepted a wrong ArgoCD secret key"
  fi

  cp "${webhook}" "${tmp}/wrong-target.yaml"
  yq -i '.spec.target.name = "replacement-secret" | .spec.target.creationPolicy = "Owner"' "${tmp}/wrong-target.yaml"
  if webhook_contract "${tmp}/wrong-target.yaml"; then
    fail "webhook contract accepted replacement of the existing argocd-secret"
  fi

  include="$(yq -r '.spec.source.directory.include' registry/fleet-root.yaml)"
  grep -Fq 'argocd-webhook-secret.yaml' <<<"${include}" ||
    fail "fleet-root does not sync the ArgoCD webhook ExternalSecret"
  echo "  authenticated webhook secret: Infisical -> ESO Merge -> argocd-secret/webhook.github.secret; wrong key/target rejected ✓"
  ;;
rendered-cr)
  # The compiler chart's own diene CRD kinds and rendered ArgoCD
  # ApplicationSets validate against frozen schemas. Project/Stage remain
  # upstream Kargo kinds without a diene slice. Warehouse uses pinned Kargo
  # v1.9.10 validation; CloudflareDeploy including optional rollout validates
  # against the frozen T3 shape.
  render >"${tmp}/r.yaml"
  kubeconform -strict -summary \
    -schema-location default \
    -schema-location 'schemas/{{ .ResourceKind }}.json' \
    -skip Project,Stage \
    "${tmp}/r.yaml"
  # Deterministic negative: fleet ApplicationSets require Go templating for
  # generator variables and the templatePatch row guard.
  yq eval-all 'select(.kind == "ApplicationSet")' "${tmp}/r.yaml" >"${tmp}/invalid-applicationset.yaml"
  yq -i '.spec.goTemplate = false' "${tmp}/invalid-applicationset.yaml"
  if kubeconform -strict -summary \
    -schema-location default \
    -schema-location 'schemas/{{ .ResourceKind }}.json' \
    "${tmp}/invalid-applicationset.yaml" >/dev/null 2>&1; then
    fail "ApplicationSet schema accepted goTemplate=false"
  fi
  echo "  rendered ApplicationSets validate; goTemplate=false is rejected ✓"
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
golden-mutation | golden-mutations)
  # Behavioural mutation sensitivity. Starting from the canary baseline render,
  # every accepted one-at-a-time change to a major source-B machinery section
  # MUST alter the rendered output. These are valid mutations (helm still
  # renders them), not malformed-schema negatives — they prove the golden render
  # actually consumes each section rather than dropping it on the floor.
  render >"${tmp}/base.yaml"
  mut() {
    local label="$1" expr="$2"
    cp "${fixture}" "${tmp}/m.yaml"
    yq -i "${expr}" "${tmp}/m.yaml"
    helm template "${release}" "${chart}" --namespace "${namespace}" \
      --values "${services}" --values "${tmp}/m.yaml" >"${tmp}/m.out" 2>"${tmp}/m.err" ||
      fail "mutation '${label}' was rejected — expected a valid accepted mutation: $(tail -1 "${tmp}/m.err")"
    cmp -s "${tmp}/base.yaml" "${tmp}/m.out" &&
      fail "mutation '${label}' left the rendered output unchanged (section not wired into the render)"
    echo "  ${label} → render changed ✓"
  }
  mut "platform/Infisical identity (projectSlug)" '.infisical.projectSlug = "canary-alt"'
  mut "platform/Infisical identity (sos.register)" '.sos.register = false'
  mut "stages (object-form soak)" '.stages[1][1].soak = "2h"'
  mut "dependencies.database (neon representative)" '.dependencies.database.maindb.cpu = 2'
  mut "dependencies.kv (upstash representative)" '.dependencies.kv.sessions.ram = "256Mi"'
  mut "dependencies.cache (dragonfly representative)" '.dependencies.cache.hot.ram = "256Mi"'
  mut "dependencies.store (tigris representative)" '.dependencies.store.assets.rotation = "off"'
  mut "virtualLandscapeServices" '.virtualLandscapeServices[0].serve = false'
  mut "webhookEngine" '.webhookEngine.retryWindow = "48h"'
  mut "cloudflareDeploy" '.cloudflareDeploy[0].tag = "0.2.0"'
  mut "problems" '.problems[0].entries[0].status = 400'
  echo "  every major source-B machinery section is render-sensitive to a valid mutation ✓"
  ;;
row-expansion)
  # Deterministic AppSet contract tier, not a live Argo reconciliation trace.
  # The temporary fixture begins with a committed row, adds a second service,
  # and supplies Secret-shaped cluster-generator inputs to prove row isolation.
  render >"${tmp}/r.yaml"
  yq eval-all -o=json 'select(.kind=="ApplicationSet")' "${tmp}/r.yaml" >"${tmp}/appset.json"
  bun ./scripts/validate/fleet-row-expansion.ts platforms "${tmp}/appset.json" ||
    fail "row-scoped AppSet expansion violated the row-isolation contract"
  ;;
machinery-pin | machinery-stable)
  # Deterministic contract tier (no live cluster/tag mutation). A throwaway local
  # git repo models the compiler chart (source A of the platforms Application).
  # Using the REAL committed revision split, canary (pinned main) observes a
  # main-only commit while a machinery-stable consumer stays on the old commit
  # until the tag moves — proven with git rev-parse in the throwaway repo only.
  f=registry/platforms-appset.yaml
  rev="$(yq -r '.spec.template.spec.sources[0].targetRevision' "${f}")"
  canary_ref="$(sed -E 's/.*canary\.carbon" *\}\}([^{]*)\{\{ *else.*/\1/' <<<"${rev}")"
  other_ref="$(sed -E 's/.*else *\}\}([^{]*)\{\{ *end.*/\1/' <<<"${rev}")"
  [ "${canary_ref}" = "main" ] ||
    fail "committed split must pin canary to main (got '${canary_ref}')"
  [ "${other_ref}" = "machinery-stable" ] ||
    fail "committed split must pin non-canary to machinery-stable (got '${other_ref}')"

  repo="${tmp}/compiler"
  mkdir -p "${repo}"
  git -C "${repo}" init -q -b main
  git -C "${repo}" config user.email fleet-test@atomi.cloud
  git -C "${repo}" config user.name fleet-test
  printf 'compiler v1\n' >"${repo}/compiler"
  git -C "${repo}" add -A && git -C "${repo}" commit -qm 'compiler v1'
  old="$(git -C "${repo}" rev-parse HEAD)"
  git -C "${repo}" tag machinery-stable
  printf 'compiler v2\n' >"${repo}/compiler"
  git -C "${repo}" add -A && git -C "${repo}" commit -qm 'compiler v2 (main-only)'
  new="$(git -C "${repo}" rev-parse HEAD)"

  resolve() { git -C "${repo}" rev-parse "$1^{commit}"; }
  [ "${old}" != "${new}" ] || fail "test setup produced identical commits"
  [ "$(resolve "${canary_ref}")" = "${new}" ] ||
    fail "canary (main) did not observe the new main-only compiler commit"
  [ "$(resolve "${other_ref}")" = "${old}" ] ||
    fail "machinery-stable consumer did not stay on the old commit before the tag moved"
  git -C "${repo}" tag -f machinery-stable >/dev/null
  [ "$(resolve "${other_ref}")" = "${new}" ] ||
    fail "machinery-stable consumer did not catch up after the tag moved"

  # Manual-sync contract from the committed AppSet: canary base template carries
  # no automated block; the templatePatch enables automated only for non-canary.
  yq -e '.spec.template.spec.syncPolicy.automated == null' "${f}" >/dev/null ||
    fail "platforms AppSet base template must leave canary manual (no automated block)"
  patch="$(yq -r '.spec.templatePatch' "${f}")"
  { grep -q 'ne .repository "canary.carbon"' <<<"${patch}" && grep -q 'automated' <<<"${patch}"; } ||
    fail "platforms AppSet templatePatch must enable automated sync only for non-canary"
  echo "  main/machinery-stable split observes main-only change, catches up on tag move, canary-manual/non-canary-auto ✓"
  ;;
kargo-row-update-contract | kargo-row-update | kargo-yaml-update-contract)
  # Fast deterministic contract model — NOT Kargo-controller e2e evidence.
  # Check the fixed configured yaml-update target against a copied real row,
  # then prove the model leaves the raw human values: block unchanged.
  render >"${tmp}/r.yaml"
  row="platforms/canary/landscapes/raichu/dummy.yaml"
  stages="$(yq eval-all -o=json '.' "${tmp}/r.yaml" | jq -s '[.[] | select(.kind=="Stage")]')"
  jq -e '
    length > 0 and
    all(.[];
      ([.spec.promotionTemplate.spec.steps[] | select(.uses=="yaml-update")] | length == 1) and
      ([.spec.promotionTemplate.spec.steps[] | select(.uses=="yaml-update") | .config.updates] |
        (length == 1) and (.[0] | type == "array" and length == 1 and .[0].key == "pin.tag"))
    )
  ' <<<"${stages}" >/dev/null ||
    fail "every rendered Stage must configure exactly one yaml-update with only pin.tag"
  update="$(jq -c --arg path "./repo/${row}" '
    [.[] | select(
      [.spec.promotionTemplate.spec.steps[] | select(.uses=="yaml-update") | .config.path] == [$path]
    )] | if length == 1 then .[0].spec.promotionTemplate.spec.steps[] | select(.uses=="yaml-update") | .config else empty end
  ' <<<"${stages}")"
  [ -n "${update}" ] || fail "exactly one Stage must target the copied Raichu row ${row}"
  key="$(jq -r '.updates[0].key' <<<"${update}")"
  [ "${key}" = "pin.tag" ] || fail "Raichu Stage yaml-update key must be pin.tag"
  yq -e 'has("values")' "${row}" >/dev/null ||
    fail "expected the raichu row to carry a human values: block"
  values_block() { awk '/^values:/{f=1} f' "$1"; }
  values_block "${row}" >"${tmp}/values.before"

  cp "${row}" "${tmp}/row.yaml"
  old_tag="$(yq -r '.pin.tag' "${tmp}/row.yaml")"
  bun ./scripts/validate/fleet-yaml-update.ts "${tmp}/row.yaml" "${key}" 0.9.9-canary ||
    fail "fast yaml-update contract model failed on the configured pin.tag target"
  new_tag="$(yq -r '.pin.tag' "${tmp}/row.yaml")"
  { [ "${new_tag}" = "0.9.9-canary" ] && [ "${new_tag}" != "${old_tag}" ]; } ||
    fail "pin.tag was not updated (${old_tag} -> ${new_tag})"
  values_block "${tmp}/row.yaml" >"${tmp}/values.after"
  cmp -s "${tmp}/values.before" "${tmp}/values.after" ||
    fail "values: block changed during a pin.tag-only update (must be byte-identical)"

  # Negative: the raw-block guard must detect a values: mutation.
  cp "${row}" "${tmp}/bad.yaml"
  bun ./scripts/validate/fleet-yaml-update.ts "${tmp}/bad.yaml" values.workload.replicas 99 ||
    fail "fast yaml-update contract model failed to seed the values: negative"
  values_block "${tmp}/bad.yaml" >"${tmp}/values.bad"
  cmp -s "${tmp}/values.before" "${tmp}/values.bad" &&
    fail "byte-identical guard failed to detect a mutated values: block"
  if bun ./scripts/validate/fleet-yaml-update.ts "${tmp}/bad.yaml" missing.path value >/dev/null 2>&1; then
    fail "fast yaml-update contract model accepted a missing update path"
  fi
  echo "  fast yaml-update contract model: exact Raichu pin.tag target, raw values bytes, and negatives ✓"
  ;;
guard)
  bash ./scripts/validate/registry-guard.sh
  ;;
presence)
  test -s docs/domain/fleet-repo.md || fail "docs/domain/fleet-repo.md missing"
  test -s .github/CODEOWNERS || fail "CODEOWNERS missing"
  test -s .github/rulesets/registry-guard-main.json || fail "registry ruleset payload missing"
  test -s scripts/local/registry-guard-apply.sh || fail "registry-guard apply script missing"
  test -s .github/workflows/registry-guard-e2e.yaml || fail "periodic registry-guard e2e workflow missing"
  test -s registry/argocd-webhook-secret.yaml || fail "ArgoCD webhook ExternalSecret missing"
  test -s "${chart}/values.schema.json" || fail "compiler chart values.schema.json missing"
  test -s "${chart}/values.schema.source.json" || fail "deliberate compiler schema source missing"
  test -s "${golden_dir}/canary.prod.yaml" || fail "prod golden render missing"
  # pin-management + webhook-wiring docs are published in the domain doc.
  rg -q '^## The `machinery-stable` tag' docs/domain/fleet-repo.md || fail "machinery-stable pin doc missing"
  rg -q '^## The `mercury-stable` pin' docs/domain/fleet-repo.md || fail "mercury-stable pin doc missing"
  rg -q '^## ArgoCD webhook wiring' docs/domain/fleet-repo.md || fail "ArgoCD webhook wiring doc missing"
  rg -q '⚠ S11 ASSUMED-GREEN' docs/domain/fleet-repo.md || fail "S11 assumption marker missing"
  rg -q 'MINUN USER-REVIEW' docs/domain/fleet-repo.md || fail "MINUN user-review marker missing"
  ;;
*)
  echo "❌ unknown validation mode '${mode}'" >&2
  exit 1
  ;;
esac

echo "✅ fleet ${mode} validation passed"
