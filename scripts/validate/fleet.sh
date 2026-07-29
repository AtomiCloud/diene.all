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
  json -e '[.[] | select(.kind=="Stage") | .metadata.labels["'"${prefix}"'/landscape"]] | sort == ["ampharos","pichu","pikachu","raichu"]' >/dev/null ||
    fail "Kargo stages do not cover exactly the registered WORKLOAD landscape set"
  # ENTEI is infrastructure-only and must never receive a Stage, a row, or any
  # rendered object — asserted on the rendered output, not only on the input.
  json -e 'all(.[]; (.metadata.labels["'"${prefix}"'/landscape"] // "") != "entei")' >/dev/null ||
    fail "an infrastructure-only landscape received a rendered object (exclusion law, ENV-SPEC §0.3)"
  # Canary dummy-service guardrail: exactly ONE service, named dummy, so canary
  # can never quietly become a second real platform to maintain.
  json -e '[.[] | select(.kind=="Warehouse") | .metadata.name] == ["dummy"]' >/dev/null ||
    fail "canary must expose exactly one service named 'dummy' (dummy-service guardrail)"
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
  policies() { yq eval-all -o=json '.' "${tmp}/r.yaml" | jq -s '.[] | select(.kind=="ProjectConfig") | .spec.promotionPolicies'; }
  auto_enabled() { policies | jq -e --arg s "$1" 'map(select(.stageSelector.name==$s and .autoPromotionEnabled==true)) | length==1' >/dev/null; }
  no_policy() { policies | jq -e --arg s "$1" 'map(select(.stageSelector.name==$s)) | length==0' >/dev/null; }

  # ---------------------------------------------------------------------------
  # FIELD-EXACT v1 Kargo mapping (goals/fleet.md: "exact, not an implementation
  # choice"). Every assertion below reads a REAL Kargo field, never an
  # annotation: an annotation cannot gate a promotion, so asserting one would be
  # a green that answers a weaker question than the one being asked.
  # Field shapes verified against the Kargo v1.9.10 CRDs
  # (projectconfigs: stageSelector.name + autoPromotionEnabled;
  #  stages: sources.{direct,stages,availabilityStrategy,requiredSoakTime}).
  # ---------------------------------------------------------------------------

  # pichu — bare first step: enabled auto-promotion policy, subscribes DIRECT to
  # the Warehouse, no verification, no required-soak.
  auto_enabled canary-dummy-pichu || fail "pichu must carry an enabled auto-promotion policy"
  stage canary-dummy-pichu | jq -e '.spec.requestedFreight[0].sources.direct==true' >/dev/null ||
    fail "first pipeline step must subscribe direct to the Warehouse"
  stage canary-dummy-pichu | jq -e '.spec.verification==null and (.spec.requestedFreight[0].sources|has("requiredSoakTime")|not)' >/dev/null ||
    fail "bare first step must omit verification and required-soak fields"

  # pikachu — object parallel member, gate: manual: NO enabling policy (absence
  # is the mechanism), requests freight from pichu, carries canary-smoke.
  no_policy canary-dummy-pikachu || fail "gate: manual must emit NO enabling promotion policy for pikachu"
  stage canary-dummy-pikachu | jq -e '.spec.requestedFreight[0].sources.stages==["canary-dummy-pichu"]' >/dev/null ||
    fail "parallel-set member must take the preceding step as upstream"
  stage canary-dummy-pikachu | jq -e '.spec.verification.analysisTemplates==[{"name":"canary-smoke"}]' >/dev/null ||
    fail "pikachu must carry exactly analysisTemplates [{name: canary-smoke}]"

  # raichu — BARE parallel member: enabled policy, upstream pichu, and no
  # verification or required-soak fields at all.
  auto_enabled canary-dummy-raichu || fail "bare parallel member raichu must carry an enabled auto-promotion policy"
  stage canary-dummy-raichu | jq -e '.spec.requestedFreight[0].sources.stages==["canary-dummy-pichu"]' >/dev/null ||
    fail "bare parallel member must take the preceding step as upstream"
  stage canary-dummy-raichu | jq -e '.spec.verification==null and (.spec.requestedFreight[0].sources|has("requiredSoakTime")|not)' >/dev/null ||
    fail "bare parallel member must omit verification and required-soak fields"

  # ampharos — the post-parallel RENDEZVOUS: enabled policy, BOTH upstream
  # members, availabilityStrategy All, 15m residency, canary-analysis.
  auto_enabled canary-dummy-ampharos || fail "ampharos rendezvous must carry an enabled auto-promotion policy"
  stage canary-dummy-ampharos | jq -e '.spec.requestedFreight[0].sources.stages==["canary-dummy-pikachu","canary-dummy-raichu"]' >/dev/null ||
    fail "step after a parallel set must rendezvous on ALL members, in order"
  stage canary-dummy-ampharos | jq -e '.spec.requestedFreight[0].sources.availabilityStrategy=="All"' >/dev/null ||
    fail "rendezvous must set sources.availabilityStrategy: All (Kargo defaults to OneOf — omitting it silently weakens the gate)"
  stage canary-dummy-ampharos | jq -e '.spec.requestedFreight[0].sources.requiredSoakTime=="15m"' >/dev/null ||
    fail "rendezvous must map soak to sources.requiredSoakTime: 15m"
  stage canary-dummy-ampharos | jq -e '.spec.verification.analysisTemplates==[{"name":"canary-analysis"}]' >/dev/null ||
    fail "ampharos must carry exactly analysisTemplates [{name: canary-analysis}]"

  # Every Stage retains the fixed git-update promotion template, identical for
  # auto and manual gates, and updates ONLY the pin.
  yq eval-all -o=json '.' "${tmp}/r.yaml" | jq -s -e '
    [.[] | select(.kind=="Stage")] as $s
    | ($s|length) == 4
    and all($s[]; [.spec.promotionTemplate.spec.steps[].uses] == ["git-clone","yaml-update","git-commit","git-push"])
    and all($s[]; [.spec.promotionTemplate.spec.steps[] | select(.uses=="yaml-update") | .config.updates[].key] == ["pin.tag"])
    and all($s[]; [.spec.promotionTemplate.spec.steps[] | select(.uses=="yaml-update") | .config.updates[].value] == ["${{ imageFrom(\"registry.atomi.cloud/canary/dummy\").Tag }}"])
  ' >/dev/null || fail "every Stage must retain the fixed pin-only git-update promotion template with the exact native Kargo imageFrom(...).Tag value"

  echo "  stages: → Kargo v1 mapping (ProjectConfig policies / direct / preceding / rendezvous All+soak / verification / fixed pin-only template) ✓"
  ;;
dag-negative)
  # Controlled negatives over the EXACT rendered fields. Each mutates one field
  # of the ratified fixture and requires the shape assertion above to notice.
  # These are golden-diff-class negatives expressed as targeted field checks so
  # a failure names the field rather than dumping a whole-file diff.
  neg() {
    local desc="$1" expr="$2"
    cp "${fixture}" "${tmp}/neg.yaml"
    yq -i "${expr}" "${tmp}/neg.yaml"
    helm template "${release}" "${chart}" --namespace "${namespace}" \
      --values "${services}" --values "${tmp}/neg.yaml" >"${tmp}/neg-render.yaml" 2>/dev/null || {
      echo "    ${desc} → rejected at render ✓"
      return 0
    }
    cmp -s "${golden_dir}/canary.prod.yaml" "${tmp}/neg-render.yaml" &&
      fail "negative '${desc}' produced a render IDENTICAL to the golden — the mutation is invisible"
    echo "    ${desc} → golden diff detected ✓"
  }
  # remove the rendezvous soak
  neg "rendezvous soak removed" 'del(.stages[2].soak)'
  # flip the rendezvous gate to manual (drops its enabling policy)
  neg "rendezvous gate flipped to manual" '.stages[2].gate = "manual"'
  # flip the manual parallel member to auto (adds an enabling policy)
  neg "manual member flipped to auto" '.stages[1][0].gate = "auto"'
  # rename an analysis template
  neg "analysis template renamed" '.stages[2].verification.analysisTemplates[0] = "not-canary-analysis"'
  # drop verification from the manual member
  neg "manual member verification removed" 'del(.stages[1][0].verification)'

  # ---------------------------------------------------------------------------
  # RENDER-TAMPER negatives — prove the `dag` field assertions are NON-VACUOUS.
  # The two mutations the goal names by name (dropping `availabilityStrategy:
  # All`, and dropping an upstream stage name from the rendezvous) cannot be
  # reached from the INPUT: the parallel set's minItems:2 rejects the collapsed
  # DAG at the schema, so an input mutation would only re-test the schema. These
  # tamper the RENDERED output directly and require the exact assertion the
  # `dag` mode runs to go red — i.e. they test the guard, not the input.
  # ---------------------------------------------------------------------------
  render >"${tmp}/t.yaml"
  # Both dollar-brace forms are literal Kargo inputs, not shell expansions.
  # shellcheck disable=SC2016
  bad_pipe_value='${{ imageFrom "registry.atomi.cloud/canary/dummy" | .Tag }}'
  # shellcheck disable=SC2016
  exact_yaml_update_value='${{ imageFrom("registry.atomi.cloud/canary/dummy").Tag }}'
  tamper() {
    local desc="$1" mutate="$2" assert="$3"
    yq eval-all -o=json '.' "${tmp}/t.yaml" |
      jq -s --arg bad_pipe_value "$bad_pipe_value" --arg exact_yaml_update_value "$exact_yaml_update_value" "${mutate}" >"${tmp}/tampered.json"
    if jq -e --arg exact_yaml_update_value "$exact_yaml_update_value" "${assert}" "${tmp}/tampered.json" >/dev/null 2>&1; then
      fail "VACUOUS GUARD: '${desc}' still satisfied the dag assertion — that assertion proves nothing"
    fi
    echo "    ${desc} → dag assertion goes red ✓"
  }
  tamper "availabilityStrategy: All deleted from the rendezvous" \
    'map(if .kind=="Stage" and .metadata.name=="canary-dummy-ampharos" then del(.spec.requestedFreight[0].sources.availabilityStrategy) else . end)' \
    'any(.[]; .kind=="Stage" and .metadata.name=="canary-dummy-ampharos" and .spec.requestedFreight[0].sources.availabilityStrategy=="All")'
  tamper "one upstream stage name dropped from the rendezvous" \
    'map(if .kind=="Stage" and .metadata.name=="canary-dummy-ampharos" then .spec.requestedFreight[0].sources.stages = ["canary-dummy-raichu"] else . end)' \
    'any(.[]; .kind=="Stage" and .metadata.name=="canary-dummy-ampharos" and .spec.requestedFreight[0].sources.stages==["canary-dummy-pikachu","canary-dummy-raichu"])'
  tamper "requiredSoakTime deleted from the rendezvous" \
    'map(if .kind=="Stage" and .metadata.name=="canary-dummy-ampharos" then del(.spec.requestedFreight[0].sources.requiredSoakTime) else . end)' \
    'any(.[]; .kind=="Stage" and .metadata.name=="canary-dummy-ampharos" and .spec.requestedFreight[0].sources.requiredSoakTime=="15m")'
  tamper "manual pikachu granted an enabling promotion policy" \
    'map(if .kind=="ProjectConfig" then .spec.promotionPolicies += [{"stageSelector":{"name":"canary-dummy-pikachu"},"autoPromotionEnabled":true}] else . end)' \
    '[.[] | select(.kind=="ProjectConfig") | .spec.promotionPolicies[] | select(.stageSelector.name=="canary-dummy-pikachu")] | length==0'
  # The jq variables below are populated by --arg, not expanded by the shell.
  # shellcheck disable=SC2016
  tamper "yaml-update value uses the invalid Go-template pipe" \
    'map(if .kind=="Stage" then (.spec.promotionTemplate.spec.steps[] | select(.uses=="yaml-update") | .config.updates[].value) = $bad_pipe_value else . end)' \
    'all(.[]; (.kind != "Stage") or ([.spec.promotionTemplate.spec.steps[] | select(.uses=="yaml-update") | .config.updates[].value] == [$exact_yaml_update_value]))'

  echo "  controlled DAG negatives visible in the render, and the dag assertions proven non-vacuous ✓"
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
  # registry/clusters is ABSENT while the v1 serving roster is unratified (its
  # emptiness IS the encoded refusal), so it is included only when it exists —
  # host-pool's live ENTEI row will populate it.
  live_targets=(registry/landscapes registry/virtual-landscapes
    registry/fleet-root.yaml registry/argocd-webhook-secret.yaml
    registry/platforms-appset.yaml)
  [ -d registry/clusters ] && live_targets+=(registry/clusters)
  kubeconform -strict -summary \
    -schema-location default \
    -schema-location 'schemas/{{ .ResourceKind }}.json' \
    "${live_targets[@]}"

  # Deterministic negative: Applications may not declare an empty source URL.
  cp registry/fleet-root.yaml "${tmp}/invalid-application.yaml"
  yq -i '.spec.source.repoURL = ""' "${tmp}/invalid-application.yaml"
  if kubeconform -strict -summary \
    -schema-location default \
    -schema-location 'schemas/{{ .ResourceKind }}.json' \
    "${tmp}/invalid-application.yaml" >/dev/null 2>&1; then
    fail "Application schema accepted an empty source repoURL"
  fi
  # Topology FIXTURES are schema-valid too — that is the whole point of proving
  # a shape rather than a value. They are validated here and excluded from the
  # live-set assertions in `registry-manifest`.
  kubeconform -strict -summary \
    -schema-location default \
    -schema-location 'schemas/{{ .ResourceKind }}.json' \
    registry/fixtures/landscapes registry/fixtures/clusters \
    registry/fixtures/negative/entei-traffic-true.yaml \
    registry/fixtures/negative/second-infrastructure-landscape.yaml \
    registry/fixtures/negative/second-infrastructure-cluster.yaml

  echo "  registry CRs + topology fixtures validate against frozen schemas; invalid Application source is rejected ✓"
  ;;
registry-manifest)
  # ---------------------------------------------------------------------------
  # The ratified registry roster, asserted mechanically (goals/fleet.md DoD:
  # "asserted by a registry-manifest CI check, not review convention").
  #
  # SCOPE NOTE: canonical-spelling checks run over SEMANTIC FIELDS AND PATHS
  # only — never over comment prose. Several files legitimately name the stale
  # variant while explaining that it is stale; a gate that banned the string
  # outright would forbid documenting its own rule.
  # ---------------------------------------------------------------------------
  workload=(pichu pikachu raichu ampharos)
  live_landscapes="registry/landscapes"
  live_clusters="registry/clusters"
  live_vlandscapes="registry/virtual-landscapes"

  live_rows_in() {
    [ -d "$1" ] || return 0
    find "$1" -type f -name '*.yaml' | sort
  }

  names_in() {
    # semantic identity of every live CR in a directory: metadata.name
    [ -d "$1" ] || return 0
    find "$1" -type f -name '*.yaml' -print0 | sort -z |
      xargs -0 -r -n1 yq -r '.metadata.name'
  }

  # --- (1) live Landscape set is EXACTLY the four workload rows (+ optional entei)
  actual_landscapes="$(names_in "${live_landscapes}" | sort | tr '\n' ' ' | sed 's/ $//')"
  expected_landscapes="$(printf '%s\n' "${workload[@]}" | sort | tr '\n' ' ' | sed 's/ $//')"
  # NOTE: `printf '%s\nentei\n' ${workload}` would REUSE the format per argument
  # and emit `entei` four times. Feed entei as a trailing argument instead.
  expected_with_entei="$(printf '%s\n' "${workload[@]}" entei | sort | tr '\n' ' ' | sed 's/ $//')"
  if [ "${actual_landscapes}" != "${expected_landscapes}" ] && [ "${actual_landscapes}" != "${expected_with_entei}" ]; then
    fail "registry/landscapes must contain exactly [${expected_landscapes}] (plus the optional infrastructure-only 'entei' row landed by host-pool) — found [${actual_landscapes}]"
  fi

  # --- (2) the LIVE ENTEI pair is mutually exclusive: no ENTEI Landscape
  # permits no cluster rows; one ENTEI Landscape permits exactly its one
  # authoritative host row. This refuses every serving row until the owner
  # publishes the serving-cluster roster, without guessing any coordinates.
  mapfile -t entei_landscape_rows < <(
    while IFS= read -r manifest; do
      if yq -e '.kind == "Landscape" and .metadata.name == "entei"' "$manifest" >/dev/null 2>&1; then
        printf '%s\n' "$manifest"
      fi
    done < <(live_rows_in "$live_landscapes")
  )
  mapfile -t live_cluster_rows < <(live_rows_in "$live_clusters")

  case "${#entei_landscape_rows[@]}" in
  0)
    [ "${#live_cluster_rows[@]}" -eq 0 ] ||
      fail "no live ENTEI Landscape requires registry/clusters to contain zero live ClusterRegistration rows"
    ;;
  1)
    entei_landscape="${entei_landscape_rows[0]}"
    yq -e '.spec.purpose == "infrastructure-only"' "$entei_landscape" >/dev/null ||
      fail "a live ENTEI Landscape must carry spec.purpose: infrastructure-only"
    [ "${#live_cluster_rows[@]}" -eq 1 ] ||
      fail "one live ENTEI Landscape requires exactly one live ClusterRegistration row"

    entei_cluster="${live_cluster_rows[0]}"
    yq -e '.kind == "ClusterRegistration"' "$entei_cluster" >/dev/null ||
      fail "the single live ENTEI row must be a ClusterRegistration"
    entei_mark="$(yq -r '.spec.mark // ""' "$entei_cluster")"
    [ -n "$entei_mark" ] ||
      fail "the live ENTEI ClusterRegistration must carry a non-empty spec.mark"
    entei_name="entei-$entei_mark"
    # The diagnostic names the literal schema field `${spec.mark}`.
    # shellcheck disable=SC2016
    [ "$(yq -r '.metadata.name // ""' "$entei_cluster")" = "$entei_name" ] ||
      fail 'the live ENTEI ClusterRegistration name must equal entei-${spec.mark}'
    yq -e '.spec.landscape == "entei"' "$entei_cluster" >/dev/null ||
      fail "the live ENTEI ClusterRegistration must set spec.landscape: entei"
    yq -e '.metadata.labels["atomi.cloud/landscape"] == "entei"' "$entei_cluster" >/dev/null ||
      fail "the live ENTEI ClusterRegistration must set label atomi.cloud/landscape: entei"
    yq -e '.spec.hostRole == "anonymous-vcluster-host"' "$entei_cluster" >/dev/null ||
      fail "the live ENTEI ClusterRegistration must set spec.hostRole: anonymous-vcluster-host"
    yq -e '.spec.originMode == "loadbalancer"' "$entei_cluster" >/dev/null ||
      fail "the live ENTEI ClusterRegistration must set spec.originMode: loadbalancer"
    yq -e '.spec.traffic == false' "$entei_cluster" >/dev/null ||
      fail "the live ENTEI ClusterRegistration must set spec.traffic: false"
    ;;
  *)
    fail "registry/landscapes may contain at most one live ENTEI Landscape row"
    ;;
  esac

  # --- (3) forbidden identities: Garden-managed, hosted instance types, retired
  mapfile -t live_manifests < <(
    {
      live_rows_in "$live_landscapes"
      live_rows_in "$live_clusters"
      live_rows_in "$live_vlandscapes"
    } | sort
  )
  live_identities=""
  if [ "${#live_manifests[@]}" -gt 0 ]; then
    live_identities="$(yq eval-all -o=json '.' "${live_manifests[@]}" |
      jq -rs -r '.[] | [(.metadata.name // ""), (.spec.landscape // "")] + (.spec.hosts // []) | .[]')"
  fi
  for forbidden_name in primordial lapras ditto rotom absol eevee castform plusle minun; do
    grep -Fxq "$forbidden_name" <<<"$live_identities" &&
      fail "forbidden identity '$forbidden_name' appears in the live registry — Garden-managed, hosted-instance, and retired identities never get a registry row"
  done

  # --- (4) canonical spelling in SEMANTIC FIELDS and PATHS (never in prose)
  # Compile the semantic fields once, rather than launching yq once per file:
  # this gate runs inside every controlled-negative copy.
  mapfile -d '' -t semantic_manifests < <(
    find "${live_landscapes}" "${live_clusters}" "${live_vlandscapes}" registry/fixtures platforms -type f -name '*.yaml' -print0 2>/dev/null | sort -z
  )
  if [ "${#semantic_manifests[@]}" -gt 0 ] &&
    yq eval-all -o=json '.' "${semantic_manifests[@]}" |
    jq -s -e 'any(.[]; [(.metadata.name // ""), (.spec.landscape // ""), (.metadata.labels["atomi.cloud/landscape"] // "")] + (.spec.hosts // []) | any(. == "amphoros"))' >/dev/null; then
    fail "stale spelling 'amphoros' in a semantic field — the canonical registry spelling is 'ampharos'"
  fi

  while IFS= read -r stale_path; do
    [ -n "${stale_path}" ] && fail "stale spelling 'amphoros' in a committed PATH: ${stale_path}"
  done < <(find registry platforms -depth -name '*amphoros*' 2>/dev/null)

  # --- (5) virtual-landscape envelopes are EXACTLY mew + celebi with exact hosts
  actual_vl="$(names_in "${live_vlandscapes}" | sort | tr '\n' ' ' | sed 's/ $//')"
  [ "${actual_vl}" = "celebi mew" ] ||
    fail "registry/virtual-landscapes must contain exactly [celebi mew] — found [${actual_vl}]"
  # NOTE: mikefarah yq's `==` does not perform deep ARRAY equality (it returns
  # false for equal arrays), so every ordered-list assertion in this file goes
  # through jq. Using yq here would produce a permanently-false check that reads
  # like a passing guard.
  yq -o=json '.spec.hosts' "${live_vlandscapes}/mew.yaml" | jq -e '. == ["raichu","ampharos"]' >/dev/null ||
    fail "mew envelope hosts must be exactly [raichu, ampharos]"
  yq -o=json '.spec.hosts' "${live_vlandscapes}/celebi.yaml" | jq -e '. == ["pikachu"]' >/dev/null ||
    fail "celebi envelope hosts must be exactly [pikachu]"

  # --- (6) placeholder-live-path refusal
  while IFS= read -r manifest; do
    [ -z "${manifest}" ] && continue
    placeholders="$(yq -r '[.. | select(tag == "!!str")] | map(select(test("<[A-Za-z-]+>"))) | join(",")' "${manifest}" 2>/dev/null || true)"
    [ -z "${placeholders}" ] && continue
    fail "placeholder ${placeholders} committed under a LIVE registry path: ${manifest} — placeholders belong in registry/fixtures/ only"
  done < <(find "${live_landscapes}" "${live_clusters}" "${live_vlandscapes}" -type f -name '*.yaml' 2>/dev/null | sort)

  # --- (7) fleet-root must NOT sync the fixtures tree
  include_glob="$(yq -r '.spec.source.directory.include' registry/fleet-root.yaml)"
  case "${include_glob}" in
  *fixtures*) fail "registry/fleet-root.yaml's include glob covers fixtures/ — ArgoCD would APPLY the negative fixtures as real objects" ;;
  esac
  yq -e '.spec.source.directory.include | test("landscapes/\*\.yaml")' registry/fleet-root.yaml >/dev/null ||
    fail "registry/fleet-root.yaml must keep its explicit include allowlist"

  echo "  live roster exact · entei invariant · forbidden identities absent · canonical spelling · envelopes exact · no guessed serving rows · no live-path placeholders · fixtures unsynced ✓"
  ;;
registry-manifest-negative)
  # ---------------------------------------------------------------------------
  # Proves the registry-manifest gate is NON-VACUOUS. Each case copies the live
  # registry into a throwaway tree, plants ONE violation, and requires the gate
  # to reject it. Without this, every assertion above is an untested claim.
  #
  # The baseline is the ruled live registry. Each controlled negative must fail
  # for its OWN mutation, and case 0 proves the unmodified baseline is green.
  # ---------------------------------------------------------------------------
  self="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/scripts/validate/fleet.sh"
  base="${tmp}/base"
  mkdir -p "${base}"
  cp -r registry platforms "${base}/"

  run_case() {
    local desc="$1" expect="$2"
    shift 2
    local work="${tmp}/case-$$-${RANDOM}"
    cp -r "${base}" "${work}"
    (cd "${work}" && "$@")
    if (cd "${work}" && bash "${self}" registry-manifest >/dev/null 2>&1); then
      [ "${expect}" = "pass" ] && {
        echo "    ${desc} → gate green ✓"
        return 0
      }
      fail "VACUOUS GATE: '${desc}' was ACCEPTED by registry-manifest"
    else
      [ "${expect}" = "fail" ] && {
        echo "    ${desc} → gate red ✓"
        return 0
      }
      fail "gate rejected the baseline it should accept: ${desc}"
    fi
  }

  # A controlled negative must fail for its own mutation. Requiring the expected
  # diagnostic also proves the exact gate branch fired.
  run_reject() {
    local desc="$1" needle="$2"
    shift 2
    local work="$tmp/case-$$-$RANDOM"
    cp -r "$base" "$work"
    (cd "$work" && "$@")
    local output
    if output="$(cd "$work" && bash "$self" registry-manifest 2>&1)"; then
      fail "VACUOUS GATE: '$desc' was ACCEPTED by registry-manifest"
    fi
    grep -Fq "$needle" <<<"$output" ||
      fail "wrong rejection for '$desc' (expected '$needle'): $output"
    echo "    $desc → expected gate branch red ✓"
  }

  live_entei_landscape() {
    sed 's/<RATIFIED-HOST-REGION>/us-test-1/' registry/fixtures/landscapes/entei.yaml >registry/landscapes/entei.yaml
  }
  live_entei_cluster() {
    mkdir -p registry/clusters
    sed -e 's/<mark>/jade/g' -e 's/<provider>/ratified-provider/g' \
      registry/fixtures/clusters/entei-mark.yaml >registry/clusters/entei-jade.yaml
  }
  live_entei_pair() {
    live_entei_landscape
    live_entei_cluster
  }
  non_entei_host_row() {
    live_entei_cluster
    yq -i '.metadata.name = "suicune-jade" | .metadata.labels["atomi.cloud/landscape"] = "suicune" | .spec.landscape = "suicune"' registry/clusters/entei-jade.yaml
    mv registry/clusters/entei-jade.yaml registry/clusters/suicune-jade.yaml
  }
  wrong_entei_cluster_landscape() {
    live_entei_pair
    yq -i '.spec.landscape = "suicune"' registry/clusters/entei-jade.yaml
  }
  wrong_entei_cluster_label() {
    live_entei_pair
    yq -i '.metadata.labels["atomi.cloud/landscape"] = "suicune"' registry/clusters/entei-jade.yaml
  }
  entei_name_mark_mismatch() {
    live_entei_pair
    yq -i '.metadata.name = "entei-onyx"' registry/clusters/entei-jade.yaml
  }
  second_entei_host_row() {
    live_entei_pair
    cp registry/clusters/entei-jade.yaml registry/clusters/entei-onyx.yaml
    yq -i '.metadata.name = "entei-onyx" | .spec.mark = "onyx"' registry/clusters/entei-onyx.yaml
  }
  entei_missing_origin_mode() {
    live_entei_pair
    yq -i 'del(.spec.originMode)' registry/clusters/entei-jade.yaml
  }
  entei_wrong_origin_mode() {
    live_entei_pair
    yq -i '.spec.originMode = "clusterip"' registry/clusters/entei-jade.yaml
  }
  entei_traffic_true() {
    live_entei_landscape
    mkdir -p registry/clusters
    sed -e 's/<mark>/jade/g' -e 's/<provider>/ratified-provider/g' \
      registry/fixtures/negative/entei-traffic-true.yaml >registry/clusters/entei-jade.yaml
  }
  entei_missing_purpose() {
    live_entei_pair
    yq -i 'del(.spec.purpose)' registry/landscapes/entei.yaml
  }

  run_case "ruled live-registry baseline" pass true
  run_reject "extra live landscape (suicune)" \
    "registry/landscapes must contain exactly" \
    cp registry/fixtures/negative/second-infrastructure-landscape.yaml registry/landscapes/suicune.yaml
  run_reject "Garden-managed lapras identity" \
    "forbidden identity 'lapras'" \
    yq -i '.spec.hosts = ["lapras","ampharos"]' registry/virtual-landscapes/mew.yaml
  run_reject "retired plusle identity" \
    "forbidden identity 'plusle'" \
    yq -i '.spec.hosts = ["raichu","plusle"]' registry/virtual-landscapes/mew.yaml
  run_reject "stale spelling in a semantic field" \
    "stale spelling 'amphoros' in a semantic field" \
    yq -i '.metadata.labels["atomi.cloud/landscape"] = "amphoros"' registry/landscapes/ampharos.yaml
  run_reject "stale spelling in a committed PATH" \
    "stale spelling 'amphoros' in a committed PATH" \
    mv registry/landscapes/ampharos.yaml registry/landscapes/amphoros.yaml
  run_reject "mew envelope host set altered" \
    "mew envelope hosts must be exactly [raichu, ampharos]" \
    yq -i '.spec.hosts = ["raichu"]' registry/virtual-landscapes/mew.yaml
  run_reject "celebi envelope removed" \
    "registry/virtual-landscapes must contain exactly [celebi mew]" \
    rm registry/virtual-landscapes/celebi.yaml
  run_reject "arbitrary non-ENTEI host-role/traffic row" \
    "no live ENTEI Landscape requires registry/clusters to contain zero live ClusterRegistration rows" \
    non_entei_host_row
  run_reject "live ENTEI row with traffic: true" \
    "the live ENTEI ClusterRegistration must set spec.traffic: false" \
    entei_traffic_true
  run_reject "live ENTEI Landscape missing its purpose" \
    "a live ENTEI Landscape must carry spec.purpose: infrastructure-only" \
    entei_missing_purpose
  run_reject "placeholder promoted into a live path" \
    "placeholder <UNRATIFIED-REGION> committed under a LIVE registry path" \
    yq -i '.spec.region = "<UNRATIFIED-REGION>"' registry/landscapes/pichu.yaml
  run_reject "fleet-root taught to sync fixtures" \
    "registry/fleet-root.yaml's include glob covers fixtures/" \
    yq -i '.spec.source.directory.include = "{landscapes/*.yaml,fixtures/**/*.yaml}"' registry/fleet-root.yaml

  # the ONE shape the gate must accept: host-pool's live ENTEI pair under its invariant
  run_case "host-pool lands the live ENTEI pair under its invariant" pass live_entei_pair

  run_reject "ENTEI row with wrong spec.landscape" \
    "the live ENTEI ClusterRegistration must set spec.landscape: entei" \
    wrong_entei_cluster_landscape
  run_reject "ENTEI row with wrong landscape label" \
    "the live ENTEI ClusterRegistration must set label atomi.cloud/landscape: entei" \
    wrong_entei_cluster_label
  # The expected diagnostic names the literal schema field `${spec.mark}`.
  # shellcheck disable=SC2016
  run_reject "ENTEI name and mark mismatch" \
    'the live ENTEI ClusterRegistration name must equal entei-${spec.mark}' \
    entei_name_mark_mismatch
  run_reject "second ENTEI host row" \
    "one live ENTEI Landscape requires exactly one live ClusterRegistration row" \
    second_entei_host_row
  run_reject "Landscape-only ENTEI pair" \
    "one live ENTEI Landscape requires exactly one live ClusterRegistration row" \
    live_entei_landscape
  run_reject "ClusterRegistration-only ENTEI pair" \
    "no live ENTEI Landscape requires registry/clusters to contain zero live ClusterRegistration rows" \
    live_entei_cluster
  run_reject "ENTEI row missing originMode" \
    "the live ENTEI ClusterRegistration must set spec.originMode: loadbalancer" \
    entei_missing_origin_mode
  run_reject "ENTEI row with wrong originMode" \
    "the live ENTEI ClusterRegistration must set spec.originMode: loadbalancer" \
    entei_wrong_origin_mode

  echo "  registry-manifest gate proven non-vacuous across 20 violations + 2 accepted shapes ✓"
  ;;
registry-exclusion)
  # ---------------------------------------------------------------------------
  # The exclusion law keys on purpose/hostRole, NOT on the literal name `entei`.
  # A second, differently named infrastructure-only pair must be excluded
  # IDENTICALLY — this is the only assertion that catches a name-special-cased
  # gate (host-pool §1).
  # ---------------------------------------------------------------------------
  entei_l=registry/fixtures/landscapes/entei.yaml
  second_l=registry/fixtures/negative/second-infrastructure-landscape.yaml
  second_c=registry/fixtures/negative/second-infrastructure-cluster.yaml

  [ "$(yq -r '.metadata.name' "${second_l}")" != "entei" ] ||
    fail "the second infrastructure-only fixture must NOT be named entei — it exists to prove the exclusion is not name-keyed"

  # both infrastructure-only landscapes carry the same discriminator
  for f in "${entei_l}" "${second_l}"; do
    yq -e '.spec.purpose == "infrastructure-only"' "${f}" >/dev/null ||
      fail "${f} must carry spec.purpose: infrastructure-only"
  done
  # both host clusters carry the same role + traffic invariant
  for f in registry/fixtures/clusters/entei-mark.yaml "${second_c}"; do
    yq -e '.spec.hostRole == "anonymous-vcluster-host" and .spec.traffic == false' "${f}" >/dev/null ||
      fail "${f} must carry hostRole: anonymous-vcluster-host and traffic: false"
  done

  # traffic-true negative is schema-VALID but semantically rejected
  kubeconform -strict -summary -schema-location default \
    -schema-location 'schemas/{{ .ResourceKind }}.json' \
    registry/fixtures/negative/entei-traffic-true.yaml >/dev/null ||
    fail "the traffic-true negative must stay schema-valid, so the rejection proves the INVARIANT rather than the schema"
  yq -e '.spec.traffic == true and .spec.hostRole == "anonymous-vcluster-host"' \
    registry/fixtures/negative/entei-traffic-true.yaml >/dev/null ||
    fail "the traffic-true negative no longer expresses the violation it exists to encode"

  # a platform.yaml declaring an infrastructure-only landscape must be REJECTED
  # by the closed registeredLandscape enum, before any object is rendered.
  if helm template "${release}" "${chart}" --namespace "${namespace}" \
    --values "${services}" --values registry/fixtures/negative/platform-declares-entei.yaml >/dev/null 2>&1; then
    fail "a platform.yaml declaring 'entei' in landscapes:/stages: was RENDERED — the exclusion law is not enforced"
  fi
  # ...and so must one naming the SECOND infrastructure-only landscape, proving
  # the rejection is structural rather than a special case for `entei`.
  cp registry/fixtures/negative/platform-declares-entei.yaml "${tmp}/second-infra-platform.yaml"
  yq -i '(.landscapes[] | select(. == "entei")) = "suicune" | (.stages[] | select(. == "entei")) = "suicune"' "${tmp}/second-infra-platform.yaml"
  if helm template "${release}" "${chart}" --namespace "${namespace}" \
    --values "${services}" --values "${tmp}/second-infra-platform.yaml" >/dev/null 2>&1; then
    fail "a platform.yaml declaring the SECOND infrastructure-only landscape rendered — the exclusion is name-keyed, not purpose-keyed"
  fi

  # canary declares exactly the four workload landscapes, and never entei
  yq -o=json '.landscapes' "${fixture}" | jq -e '. == ["pichu","pikachu","raichu","ampharos"]' >/dev/null ||
    fail "canary must declare exactly the four registered WORKLOAD landscapes"

  echo "  infrastructure-only exclusion keyed on purpose/hostRole (proven with a second, differently named pair) ✓"
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
  # upstream Kargo kinds without a diene slice. Warehouse and ProjectConfig use
  # pinned Kargo v1.9.10 slices; CloudflareDeploy including optional rollout
  # validates against the frozen T3 shape.
  #
  # ProjectConfig is deliberately NOT skipped: it is the CR that actually gates
  # promotion, and `gate: manual` is realized as the ABSENCE of an enabling
  # policy — a distinction an unvalidated render could lose silently.
  render >"${tmp}/r.yaml"
  yq eval-all -o=json 'select(.kind == "ApplicationSet")' "${tmp}/r.yaml" >"${tmp}/applicationset.json"
  jq -e '
    .spec.generators[1].matrix.generators[1].clusters.selector.matchExpressions == [{
      key:"atomi.cloud/cluster-role", operator:"NotIn", values:["infrastructure-only"]
    }]
  ' "${tmp}/applicationset.json" >/dev/null ||
    fail "rendered ApplicationSet lost the exact infrastructure-only cluster-role exclusion"
  kubeconform -strict -summary \
    -schema-location default \
    -schema-location 'schemas/{{ .ResourceKind }}.json' \
    -skip Project,Stage \
    "${tmp}/r.yaml"
  # Schema negative: keep the exact selector path but make `values` a scalar.
  # Requiring the field-specific diagnostic proves this fails in the frozen
  # matchExpressions slice, not in an unrelated part of the ApplicationSet.
  jq '.spec.generators[1].matrix.generators[1].clusters.selector.matchExpressions[0].values = "infrastructure-only"' \
    "${tmp}/applicationset.json" >"${tmp}/invalid-match-expressions.json"
  if kubeconform -strict -summary \
    -schema-location default \
    -schema-location 'schemas/{{ .ResourceKind }}.json' \
    "${tmp}/invalid-match-expressions.json" >"${tmp}/invalid-match-expressions.log" 2>&1; then
    fail "ApplicationSet schema accepted scalar matchExpressions values"
  fi
  rg -q 'matchExpressions.*values|values.*matchExpressions' "${tmp}/invalid-match-expressions.log" ||
    fail "malformed matchExpressions was rejected without its field-specific schema diagnostic"
  rg -qi 'array' "${tmp}/invalid-match-expressions.log" ||
    fail "malformed matchExpressions diagnostic did not require values to be an array"
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
  echo "  rendered ApplicationSet selector validates exactly; malformed matchExpressions and goTemplate=false are rejected ✓"
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
  as | jq -e '.spec.generators[1].matrix.generators[1].clusters.selector.matchExpressions == [{key:"'"${prefix}"'/cluster-role",operator:"NotIn",values:["infrastructure-only"]}]' >/dev/null ||
    fail "g2 selector must exclude infrastructure-only cluster-role Secrets"
  as | jq -e '.spec.generators[1].matrix.template.spec.sources[0].repoURL == "oci://registry.atomi.cloud/{{ .platform }}-{{ .service }}"' >/dev/null ||
    fail "g2 OCI path must consume explicit row fields"
  expected_values='{{ get . "values" | default dict | toRawJson }}'
  as | jq -e --arg expected "${expected_values}" '
    .spec.generators[0].git.template.spec.sources[0].helm.values == $expected and
    .spec.generators[1].matrix.template.spec.sources[0].helm.values == $expected
  ' >/dev/null ||
    fail "g1/g2 must access optional row values with get under missingkey=error"
  as | jq -e '.spec.templatePatch | contains("ne .platform \"canary\"") and contains("has .service") and contains("ne .service $filenameService") and contains("ne .landscape $pathLandscape")' >/dev/null ||
    fail "AppSet templatePatch must validate row fields against roster/path/filename"
  as | jq -e '[.. | strings | select(test("path\\.segments|path\\.filename"))] | length == 1' >/dev/null ||
    fail "path-derived identity leaked outside the row-validation templatePatch"
  echo "  AppSet g1/g2 uses explicit row identity, excludes infrastructure-only Secrets, and keeps fail-before-render path/roster guards ✓"
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
  yq -e '
    .spec.template.spec.sources[0].repoURL == "https://github.com/AtomiCloud/fleet" and
    .spec.template.spec.sources[2].repoURL == "https://github.com:443/AtomiCloud/fleet" and
    .spec.template.spec.sources[2].targetRevision == "HEAD" and
    .spec.template.spec.sources[2].ref == "services" and
    .spec.template.spec.sources[0].repoURL != .spec.template.spec.sources[2].repoURL
  ' "${f}" >/dev/null ||
    fail "platforms AppSet must keep the HEAD services ref on its distinct explicit-443 Git identity"
  patch="$(yq -r '.spec.templatePatch' "${f}")"
  { echo "${patch}" | grep -q 'ne .repository "canary.carbon"' && echo "${patch}" | grep -q 'automated'; } ||
    fail "platforms AppSet must disable auto-sync for canary via templatePatch"
  echo "  platforms AppSet: scmProvider *.carbon + 3-source + distinct HEAD roster identity + machinery-stable/main split + canary manual-sync ✓"
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
  mut "stages (rendezvous soak)" '.stages[2].soak = "30m"'
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
sit-host-image-binding | sit-host-image)
  # Deterministic offline model of the L9 host-image step. No docker daemon, no
  # network, no cluster, no k3d — the gate runs anywhere `bash`, `jq`, `awk` and
  # `sed` run.
  #
  # WHY THIS EXISTS. The recorded L9 abort in
  # exec/nodes/fleet/evidence/failed-sit-1ab1964-run1 (exit 1 at the export-tag
  # assertion) is a harness bug with a fully deterministic cause: `docker pull
  # name:tag@digest` stores the image under name@digest ONLY and never creates
  # name:tag, on both the classic and the containerd image stores. The pull
  # transcript in that bundle shows exactly that — Docker normalized the header
  # and Status lines to the digest-only reference. So the SIT could only ever
  # reach `k3d image import` on a machine whose daemon already happened to carry
  # that tag from an earlier tag-only pull.
  #
  # WHY IT RUNS PRODUCTION BYTES. The function under test is EXTRACTED from
  # scripts/ci/fleet-sit.sh and sourced, never transcribed here. A copy would
  # drift and could go green while the SIT stayed red.
  #
  # WHAT THE SHIM IS ALLOWED TO MODEL. Only daemon semantics that were observed
  # against a real docker 29.1.3: digest-qualified pull stores by digest; a
  # digest-qualified reference resolves whether or not it carries a tag; `docker
  # image tag` binds a new name to the source's content and overwrites any
  # previous binding. M0 below asserts the shim actually reproduces the recorded
  # failure, so a shim that trivially satisfies everything cannot pass.
  sit_source="scripts/ci/fleet-sit.sh"
  sit_fn="kargo_runtime_verify_host_image"
  sit_assert="${PWD}/scripts/validate/fleet-sit/assert.sh"
  test -s "${sit_assert}" || fail "the SIT assertion library is missing: ${sit_assert}"

  sed -n "/^${sit_fn}() {\$/,/^}\$/p" "${sit_source}" >"${tmp}/host-image-fn.sh"
  test -s "${tmp}/host-image-fn.sh" ||
    fail "could not extract ${sit_fn}() from ${sit_source}; this gate must run production bytes, never a copy"
  [ "$(tail -n 1 "${tmp}/host-image-fn.sh")" = '}' ] ||
    fail "the extracted ${sit_fn}() body is unterminated; refusing to assert on a truncated function"
  grep -q 'docker pull' "${tmp}/host-image-fn.sh" ||
    fail "the extracted ${sit_fn}() does not pull an image; the extraction is not the production function"

  # The offline driver. It is generated, not committed, so nothing here can
  # become a second copy of the production logic: it supplies the real
  # sit_fail, sources the extracted function, and shims `docker` as a shell
  # function over a plain state file of daemon-visible references.
  cat >"${tmp}/host-image-driver.sh" <<'HOSTIMAGEDRIVER'
#!/usr/bin/env bash
# Generated by scripts/validate/fleet.sh (sit-host-image-binding). Runs the
# EXTRACTED production kargo_runtime_verify_host_image bytes under the same
# `set -Eeuo pipefail` regime the SIT uses, against a docker shell-function
# shim. Never contacts a daemon, a registry, or a cluster.
set -Eeuo pipefail

assert_lib="$1" # scripts/validate/fleet-sit/assert.sh, for the real sit_fail
fn_file="$2"    # the extracted production function
state="$3"      # "<reference>\t<repo>@<digest>" per daemon-visible reference
report="$4"     # the production function appends its pull log here
image_ref="$5"
digest_ref="$6"
output="$7"

# shellcheck source=/dev/null
source "${assert_lib}"
# shellcheck source=/dev/null
source "${fn_file}"

# A digest-qualified reference resolves by digest whether or not it also
# carries a tag, so both forms normalize to the same stored key.
shim_normalize() {
  local ref="$1" name
  case "${ref}" in
  *@*)
    name="${ref%@*}"
    case "${name##*/}" in
    *:*) name="${name%:*}" ;;
    esac
    printf '%s@%s' "${name}" "${ref#*@}"
    ;;
  *) printf '%s' "${ref}" ;;
  esac
}

shim_lookup() {
  awk -F '\t' -v ref="$1" '$1 == ref { print $2; hit = 1 } END { exit hit ? 0 : 1 }' "${state}"
}

# `docker tag` overwrites an existing binding, so drop any previous row first.
shim_bind() {
  awk -F '\t' -v ref="$1" '$1 != ref' "${state}" >"${state}.next"
  mv -- "${state}.next" "${state}"
  printf '%s\t%s\n' "$1" "$2" >>"${state}"
}

docker() {
  local sub="$1"
  shift
  case "${sub}" in
  pull)
    local ref="$1" name digest recorded
    case "${ref}" in
    *@sha256:*) ;;
    *)
      echo "shim: only digest-qualified pulls are modeled: ${ref}" >&2
      return 1
      ;;
    esac
    digest="${ref#*@}"
    name="${ref%@*}"
    case "${name##*/}" in
    *:*) name="${name%:*}" ;;
    esac
    # The proven semantics: the tag is discarded and only name@digest is stored.
    recorded="${SHIM_PULL_REPODIGEST:-${name}@${digest}}"
    shim_bind "${name}@${digest}" "${recorded}"
    # Shaped like the recorded transcript in the preserved evidence bundle.
    printf '%s: Pulling from %s\nDigest: %s\nStatus: Downloaded newer image for %s\n%s\n' \
      "${name}@${digest}" "${name#*/}" "${digest}" "${name}@${digest}" "${ref}"
    ;;
  image)
    local action="$1"
    shift
    case "${action}" in
    inspect)
      local ref="$1" key repo_digest
      key="$(shim_normalize "${ref}")"
      repo_digest="$(shim_lookup "${key}")" || {
        echo "Error response from daemon: No such image: ${ref}" >&2
        return 1
      }
      # Only the fields the production assertions read are modeled.
      jq -n --arg ref "${key}" --arg repoDigest "${repo_digest}" \
        '[{Id: ($repoDigest | split("@")[1]), RepoTags: [$ref], RepoDigests: [$repoDigest]}]'
      ;;
    tag)
      local src="$1" dst="$2" repo_digest
      # A daemon that accepts the command and changes nothing. Nothing in the
      # docker CLI guarantees an error here, so the harness may not rely on one.
      [ "${SHIM_TAG_NOOP:-0}" != '1' ] || return 0
      repo_digest="$(shim_lookup "$(shim_normalize "${src}")")" || {
        echo "Error response from daemon: No such image: ${src}" >&2
        return 1
      }
      shim_bind "${dst}" "${repo_digest}"
      ;;
    *)
      echo "shim: unmodeled docker image subcommand: ${action}" >&2
      return 1
      ;;
    esac
    ;;
  *)
    echo "shim: unmodeled docker subcommand: ${sub}" >&2
    return 1
    ;;
  esac
}

if [ "${SHIM_SELFTEST:-0}" = '1' ]; then
  # M0: the shim must reproduce the recorded daemon behaviour, or every case
  # below would be asserting against a fiction.
  tag_ref="${image_ref%@*}"
  docker pull "${image_ref}" >>"${report}/kargo-runtime-image-pulls.txt" 2>&1
  docker image inspect "${image_ref}" >"${output}"
  docker image inspect "${digest_ref}" >/dev/null ||
    sit_fail 'the shim did not resolve the digest-only reference after a digest-qualified pull'
  if docker image inspect "${tag_ref}" >/dev/null 2>&1; then
    sit_fail "the shim bound ${tag_ref} on a digest-qualified pull; a real daemon does not"
  fi
  docker image tag "${digest_ref}" "${tag_ref}"
  docker image inspect "${tag_ref}" >/dev/null ||
    sit_fail "the shim did not bind ${tag_ref} after an explicit docker image tag"
  exit 0
fi

kargo_runtime_verify_host_image "${image_ref}" "${digest_ref}" "${output}"
HOSTIMAGEDRIVER

  hia_repo='example.test/kargo'
  hia_pin="sha256:$(printf 'a%.0s' {1..64})"
  hia_other="sha256:$(printf 'b%.0s' {1..64})"
  hia_tag_ref="${hia_repo}:v0.0.0"
  hia_image_ref="${hia_tag_ref}@${hia_pin}"
  hia_digest_ref="${hia_repo}@${hia_pin}"
  hia_status=0

  hia_run() {
    local dir="$1"
    mkdir -p "${dir}/report"
    : >"${dir}/report/kargo-runtime-image-pulls.txt"
    hia_status=0
    bash "${tmp}/host-image-driver.sh" \
      "${sit_assert}" \
      "${tmp}/host-image-fn.sh" \
      "${dir}/state" \
      "${dir}/report" \
      "${hia_image_ref}" \
      "${hia_digest_ref}" \
      "${dir}/image.json" \
      >"${dir}/stdout.txt" 2>"${dir}/stderr.txt" || hia_status=$?
  }

  hia_expect() {
    local label="$1" expected="$2" needle="$3" dir="$4"
    [ "${hia_status}" -eq "${expected}" ] ||
      fail "${label}: expected exit ${expected}, got ${hia_status} — $(tr '\n' ' ' <"${dir}/stderr.txt")"
    [ -z "${needle}" ] || grep -qF -- "${needle}" "${dir}/stderr.txt" ||
      fail "${label}: production failure text did not contain '${needle}' — $(tr '\n' ' ' <"${dir}/stderr.txt")"
  }

  # M0 — the shim reproduces the recorded daemon behaviour (non-vacuity of the
  # model itself, independent of which production bytes are in the tree).
  mkdir -p "${tmp}/m0"
  : >"${tmp}/m0/state"
  SHIM_SELFTEST=1
  export SHIM_SELFTEST
  hia_run "${tmp}/m0"
  unset SHIM_SELFTEST
  hia_expect 'M0 shim fidelity' 0 '' "${tmp}/m0"
  grep -q "Status: Downloaded newer image for ${hia_digest_ref}" "${tmp}/m0/report/kargo-runtime-image-pulls.txt" ||
    fail "M0 shim fidelity: the modeled pull did not normalize to the digest-only reference"
  echo "  M0 digest-qualified pull stores by digest only, never binds the tag, and an explicit tag does ✓"

  # R1 — fresh state, the exact shape of the recorded L9 failure. At the
  # baseline bytes this is red with "did not bind its export tag"; it may only
  # go green by the function itself binding the tag to the pinned digest.
  mkdir -p "${tmp}/r1"
  : >"${tmp}/r1/state"
  hia_run "${tmp}/r1"
  hia_expect 'R1 fresh digest-qualified pull' 0 '' "${tmp}/r1"
  # Asserted on the daemon model, not on the function's word: k3d v5.8 discovers
  # export inputs through RepoTags, so the tag must resolve to the pinned digest.
  grep -qxF "${hia_tag_ref}"$'\t'"${hia_digest_ref}" "${tmp}/r1/state" ||
    fail "R1 fresh digest-qualified pull: ${hia_tag_ref} is not bound to the pinned digest in the daemon model"
  test -s "${tmp}/r1/image.json" ||
    fail "R1 fresh digest-qualified pull: the digest inspection artifact was not written"
  test -s "${tmp}/r1/image-tag.json" ||
    fail "R1 fresh digest-qualified pull: the export-tag inspection artifact was not written (it feeds kargo-runtime-host-images.json)"
  jq -e --arg digest "${hia_pin}" 'any(.[0].RepoDigests[]?; endswith("@" + $digest))' \
    "${tmp}/r1/image-tag.json" >/dev/null ||
    fail "R1 fresh digest-qualified pull: the retained export-tag inspection does not carry the pinned digest"
  echo "  R1 the recorded L9 failure is gone and the export tag resolves to the pinned digest ✓"

  # R2 — a warm daemon whose :v0.0.0 tag was left pointing at DIFFERENT content
  # by an earlier tag-only pull, plus a tag command that silently does nothing.
  # An existence-only check passes here. The pinned-digest check must not.
  mkdir -p "${tmp}/r2"
  printf '%s\t%s\n' "${hia_tag_ref}" "${hia_repo}@${hia_other}" >"${tmp}/r2/state"
  SHIM_TAG_NOOP=1
  export SHIM_TAG_NOOP
  hia_run "${tmp}/r2"
  unset SHIM_TAG_NOOP
  hia_expect 'R2 stale warm-daemon tag' 1 'the export tag does not resolve to the pinned digest' "${tmp}/r2"
  echo "  R2 a stale cached tag pointing at other content is rejected, so the assertion is not existence-only ✓"

  # R3 — the pull succeeds but the pulled bytes do not carry the pin. The
  # original immutable-digest guard must still be the thing that stops it.
  mkdir -p "${tmp}/r3"
  : >"${tmp}/r3/state"
  SHIM_PULL_REPODIGEST="${hia_repo}@${hia_other}"
  export SHIM_PULL_REPODIGEST
  hia_run "${tmp}/r3"
  unset SHIM_PULL_REPODIGEST
  hia_expect 'R3 pulled bytes without the pin' 1 'host image does not carry the pinned digest' "${tmp}/r3"
  grep -qxF "${hia_tag_ref}"$'\t'"${hia_digest_ref}" "${tmp}/r3/state" &&
    fail "R3 pulled bytes without the pin: the export tag was bound even though the digest guard failed"
  echo "  R3 an image whose RepoDigests omit the pin is still rejected by the immutable-digest guard ✓"
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
