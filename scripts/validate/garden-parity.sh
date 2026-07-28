#!/usr/bin/env bash
set -euo pipefail

mode="${1:-}"
tmp="$(mktemp -d)"
trap 'rm -rf "${tmp}"' EXIT

[ -z "${mode}" ] && echo "❌ validation mode not set" >&2 && exit 1

export DIENE_PARITY_FIXTURES=true

case "${mode}" in
schema)
  # Expectations are read FROM the schema file, so this check cannot silently share a
  # defect with a hand-copied duplicate of the contract (R-E29 independent-oracle shape).
  required="$(jq -r '.required | sort | join(",")' schemas/sulfoxidemember.json)"
  profile_keys="$(jq -r '.["$defs"].profiles.required | sort | join(",")' schemas/sulfoxidemember.json)"
  reason_enum="$(jq -c '.["$defs"].state.properties.reason.enum | sort' schemas/sulfoxidemember.json)"
  while IFS= read -r -d '' file; do
    yq -o=json '.' "${file}" >"${tmp}/$(basename "${file}").json"
  done < <(find sulfoxide/members sulfoxide/fixtures/primordial sulfoxide/fixtures/negative -name '*.yaml' -print0)
  for doc in "${tmp}"/*.json; do
    jq -e --arg r "${required}" '($r | split(",")) as $req | (keys | map(select(. as $k | $req | index($k))) | length) == ($req | length)' "${doc}" >/dev/null
    jq -e --arg p "${profile_keys}" '(.profiles | keys | sort | join(",")) == $p' "${doc}" >/dev/null
    jq -e '[.profiles[] | .state] | all(. == "include" or . == "omit")' "${doc}" >/dev/null
    jq -e --argjson e "${reason_enum}" '[.profiles | to_entries[] | select(.value.state == "omit") | .value.reason] | all(. != null and (. as $x | $e | index($x)) != null)' "${doc}" >/dev/null
    jq -e '.chartRef.digest == null or (.chartRef.digest | test("^sha256:[0-9a-f]{64}$"))' "${doc}" >/dev/null
    jq -e '[.imageRefs[] | (.digest == null and .pending != null) or ((.digest // "") | test("^sha256:[0-9a-f]{64}$"))] | all' "${doc}" >/dev/null
  done
  echo "✅ Member definitions satisfy the schema-declared contract"
  ;;
profile-enum)
  yq -e '.profiles | length == 7' sulfoxide/profiles.yaml >/dev/null
  yq -o=json '[.profiles[].id]' sulfoxide/profiles.yaml | jq -e 'sort == ["absol","ditto","eevee","lapras","minun","plusle","rotom"]' >/dev/null
  yq -o=json '[.profiles[] | select(.hosted == true) | .id]' sulfoxide/profiles.yaml | jq -e 'sort == ["eevee","minun","plusle"]' >/dev/null
  echo "✅ Profile registry carries exactly the seven workload landscapes"
  ;;
no-duplicate-roster)
  # There is no roster.yaml, signed roster artifact, or Garden-owned member list: the
  # renderer must read the owning definitions and nothing else.
  ! find . -path ./.git -prune -o -name 'roster.y*ml' -print | grep -q . || {
    echo "❌ a roster file exists; the union is the owning definitions, never a third list" >&2
    exit 1
  }
  members="$(find sulfoxide/members -name '*.yaml' | wc -l | tr -d ' ')"
  homes="$(yq ea -o=json '[.]' sulfoxide/members/*.yaml | jq -r '[.[].home] | unique | join(",")')"
  [ "${homes}" != "sulfoxide" ] && echo "❌ sulfoxide/members must declare home sulfoxide only, found: ${homes}" >&2 && exit 1
  ./scripts/local/garden-render.sh all >"${tmp}/all.json"
  jq -e --argjson n "${members}" '.memberCount > $n' "${tmp}/all.json" >/dev/null
  echo "✅ Garden consumes the owning definitions; no duplicate roster exists"
  ;;
union-duplicate-negative)
  # A member authored a second time in another home must break the union.
  cp -r sulfoxide/fixtures/primordial "${tmp}/primordial"
  cp sulfoxide/fixtures/negative/duplicate-home.yaml "${tmp}/primordial/"
  DIENE_IMPORT_FILE="${tmp}/import.yaml"
  yq '.primordial.fixtures = "'"${tmp}"'/primordial"' sulfoxide/import.yaml >"${DIENE_IMPORT_FILE}"
  export DIENE_IMPORT_FILE
  ! ./scripts/local/garden-render.sh all >/dev/null 2>&1 || {
    echo "❌ the renderer accepted a member authored in two homes" >&2
    exit 1
  }
  echo "✅ A duplicated member home is rejected"
  ;;
hosted-filter)
  ./scripts/local/garden-render.sh all >"${tmp}/all.json"
  for hosted in eevee plusle minun; do
    jq -e --arg p "${hosted}" '[.profiles[$p].omitted[].id] | sort == ["boron","platinum","sulfur","xenon","zinc"]' "${tmp}/all.json" >/dev/null
    jq -e --arg p "${hosted}" '[.profiles[$p].omitted[] | select(.id == "platinum" or .id == "sulfur" or .id == "zinc" or .id == "boron") | .reason] | unique == ["entei-owns-shared-edge"]' "${tmp}/all.json" >/dev/null
    jq -e --arg p "${hosted}" '[.profiles[$p].included[].id] | index("cobalt") != null and index("dragonfly-operator") != null and index("fleet-operator") != null and index("lithium") != null' "${tmp}/all.json" >/dev/null
  done
  echo "✅ The hosted filter excludes exactly kgateway, cert-manager, issuer, and Boron while retaining dependencies, ESO, the local fleet operator, and local Logto"
  ;;
local-profile-edge)
  ./scripts/local/garden-render.sh all >"${tmp}/all.json"
  for local_profile in lapras ditto; do
    jq -e --arg p "${local_profile}" '[.profiles[$p].included[].id] | index("platinum") != null and index("boron") != null' "${tmp}/all.json" >/dev/null
  done
  for hermetic in rotom absol; do
    jq -e --arg p "${hermetic}" '[.profiles[$p].included[].id] | index("platinum") != null' "${tmp}/all.json" >/dev/null
    jq -e --arg p "${hermetic}" '[.profiles[$p].omitted[] | select(.id == "boron") | .reason] == ["connected-laptop-profiles-only"]' "${tmp}/all.json" >/dev/null
  done
  echo "✅ Local profiles own their gateway and only connected laptop profiles carry Boron"
  ;;
filter-drift-negative)
  # Dropping ESO from a hosted profile is the classic over-filter. The real hosted-filter
  # assertion must go red on it, so the sabotage runs that exact gate rather than merely
  # observing that the rendered data changed.
  cp -r sulfoxide/members "${tmp}/members"
  yq -i '.profiles.eevee = {"state": "omit", "reason": "entei-owns-shared-edge"}' "${tmp}/members/cobalt.yaml"
  ! DIENE_MEMBERS_DIR="${tmp}/members" ./scripts/validate/garden-parity.sh hosted-filter >/dev/null 2>&1 || {
    echo "❌ the hosted-filter gate stayed green after ESO left the hosted baseline" >&2
    exit 1
  }
  echo "✅ An over-filtered hosted baseline is rejected by the hosted-filter gate"
  ;;
doctor)
  DIENE_DOCTOR_REPORT="${tmp}/report.json" ./scripts/local/garden-doctor.sh definition all >"${tmp}/doctor.log"
  rg -q '📋 Included members and their pins' "${tmp}/doctor.log"
  rg -q '📋 Omissions, each with its reason' "${tmp}/doctor.log"
  jq -e '.schema == "diene-garden-parity-report/v1" and (.sourceDigest | test("^[0-9a-f]{64}$"))' "${tmp}/report.json" >/dev/null
  # Every omission in every profile is explained.
  jq -e '[.profiles[] | .omitted[] | .reason] | all(. != null)' "${tmp}/report.json" >/dev/null
  echo "✅ The doctor reports included members and explains every omission"
  ;;
doctor-installed)
  DIENE_INSTALLED_FILE=sulfoxide/fixtures/installed/eevee-green.json ./scripts/local/garden-doctor.sh installed eevee >/dev/null
  echo "✅ Installed digests match the owning definitions"
  ;;
platform-digest-acceptance)
  # A pinned image is usually an OCI index, so the digest a kubelet reports may be a
  # platform child rather than the index digest recorded in the definition. Both name the
  # same artifact and must be accepted, while an unrelated digest must still be drift.
  DIENE_PODS_JSON=sulfoxide/fixtures/cluster/pods-eevee.json ./scripts/local/garden-installed-tuple.sh eevee >"${tmp}/index.json"
  DIENE_INSTALLED_FILE="${tmp}/index.json" DIENE_INSTALLED_SUBSET=true ./scripts/local/garden-doctor.sh installed eevee >/dev/null
  DIENE_PODS_JSON=sulfoxide/fixtures/cluster/pods-eevee-platform-digests.json ./scripts/local/garden-installed-tuple.sh eevee >"${tmp}/child.json"
  DIENE_INSTALLED_FILE="${tmp}/child.json" DIENE_INSTALLED_SUBSET=true ./scripts/local/garden-doctor.sh installed eevee >/dev/null
  # The two inventories must genuinely differ, or this mode proves nothing.
  cmp -s "${tmp}/index.json" "${tmp}/child.json" && {
    echo "❌ the index and platform-child inventories are identical; this mode is vacuous" >&2
    exit 1
  }
  jq '.eevee.cobalt.images = ["sha256:9999999999999999999999999999999999999999999999999999999999999999"]' "${tmp}/child.json" >"${tmp}/bogus.json"
  ! DIENE_INSTALLED_FILE="${tmp}/bogus.json" DIENE_INSTALLED_SUBSET=true ./scripts/local/garden-doctor.sh installed eevee >/dev/null 2>&1 || {
    echo "❌ accepting platform children blunted the gate: an unrelated digest passed" >&2
    exit 1
  }
  echo "✅ An index digest and its platform children are accepted; an unrelated digest is still drift"
  ;;
cluster-inventory-shape)
  # The extractor's input shape is proven against the upstream Kubernetes schema rather
  # than against our own belief about it: kubeconform is an oracle we do not author, so a
  # fixture that drifts from what a real API server returns cannot pass (R-E29).
  kubeconform -summary -strict sulfoxide/fixtures/cluster/pods-eevee.json sulfoxide/fixtures/cluster/pods-eevee-platform-digests.json >"${tmp}/kubeconform.log" 2>&1
  rg -q "Valid: 6, Invalid: 0, Errors: 0" "${tmp}/kubeconform.log" || {
    echo "❌ the pod inventory fixture is not a schema-valid Kubernetes Pod list:" >&2
    cat "${tmp}/kubeconform.log" >&2
    exit 1
  }
  # imageID is the field the extractor depends on, so assert the schema kept it populated.
  jq -e '[.items[].status.containerStatuses[].imageID] | length == 3 and all(test("@sha256:[0-9a-f]{64}$"))' sulfoxide/fixtures/cluster/pods-eevee.json >/dev/null
  echo "✅ The pod inventory fixture is a schema-valid Pod list carrying real imageID digests"
  ;;
installed-extract)
  # The live path end to end: real kubelet imageID output becomes the tuple the doctor
  # compares, so the installed assertion does not depend on a hand-written tuple.
  DIENE_PODS_JSON=sulfoxide/fixtures/cluster/pods-eevee.json ./scripts/local/garden-installed-tuple.sh eevee >"${tmp}/tuple.json"
  jq -e '.eevee.cobalt.images[0] | test("^sha256:[0-9a-f]{64}$")' "${tmp}/tuple.json" >/dev/null
  jq -e '[.eevee | keys[]] | sort == ["chlorine","cobalt","lithium"]' "${tmp}/tuple.json" >/dev/null
  DIENE_INSTALLED_FILE="${tmp}/tuple.json" DIENE_INSTALLED_SUBSET=true ./scripts/local/garden-doctor.sh installed eevee >/dev/null
  echo "✅ A real kubelet pod inventory extracts to a tuple the doctor accepts"
  ;;
installed-extract-negative)
  # A pod running an image the owning definition does not name must be caught through the
  # same extraction path.
  jq '.items[0].status.containerStatuses[0].imageID = "ghcr.io/external-secrets/external-secrets@sha256:2222222222222222222222222222222222222222222222222222222222222222"' \
    sulfoxide/fixtures/cluster/pods-eevee.json >"${tmp}/pods.json"
  DIENE_PODS_JSON="${tmp}/pods.json" ./scripts/local/garden-installed-tuple.sh eevee >"${tmp}/tuple.json"
  ! DIENE_INSTALLED_FILE="${tmp}/tuple.json" DIENE_INSTALLED_SUBSET=true ./scripts/local/garden-doctor.sh installed eevee >/dev/null 2>&1 || {
    echo "❌ the doctor accepted a pod running an image the definition does not name" >&2
    exit 1
  }
  echo "✅ A pod running an unnamed image is rejected through the extraction path"
  ;;
doctor-installed-negative)
  ! DIENE_INSTALLED_FILE=sulfoxide/fixtures/installed/eevee-drift.json ./scripts/local/garden-doctor.sh installed eevee >/dev/null 2>&1 || {
    echo "❌ the doctor accepted an installed digest the owning definition does not name" >&2
    exit 1
  }
  echo "✅ A drifted installed digest is rejected"
  ;;
doctor-unexplained-negative)
  cp -r sulfoxide/members "${tmp}/members"
  yq -i 'del(.profiles.eevee.reason)' "${tmp}/members/platinum.yaml"
  ! DIENE_MEMBERS_DIR="${tmp}/members" ./scripts/local/garden-doctor.sh definition eevee >/dev/null 2>&1 || {
    echo "❌ the doctor accepted an omission with no reason" >&2
    exit 1
  }
  echo "✅ An unexplained omission is rejected"
  ;;
pins)
  ./scripts/local/garden-render.sh all >"${tmp}/all.json"
  # A pin is either a real digest or an openly declared pending state; never a bare guess.
  jq -e '[.profiles[] | .included[] | .images[] | (.digest != null) or (.pending != null)] | all' "${tmp}/all.json" >/dev/null
  jq -e '[.profiles[] | .included[] | .images[] | select(.digest != null) | .digest] | all(test("^sha256:[0-9a-f]{64}$"))' "${tmp}/all.json" >/dev/null
  resolved="$(jq -r '[.profiles[] | .included[] | .images[] | select(.digest != null) | .digest] | unique | length' "${tmp}/all.json")"
  [ "${resolved}" -lt 1 ] && echo "❌ no member carries a resolved image digest" >&2 && exit 1
  echo "✅ Every included pin is a real digest or a declared pending promotion (${resolved} resolved)"
  ;;
vcluster-lock)
  lock=nix/snapshots/entei-vcluster.json
  jq -e '.schema == "diene-entei-vcluster-lock/v1"' "${lock}" >/dev/null
  jq -e '.vclusterChart.digest | test("^sha256:[0-9a-f]{64}$")' "${lock}" >/dev/null
  jq -e '[.images[] | test("@sha256:[0-9a-f]{64}$")] | all' "${lock}" >/dev/null
  jq -e '.images.controlPlane | test("vcluster-oss")' "${lock}" >/dev/null
  jq -r '.images[]' "${lock}" >"${tmp}/refs.txt"
  while IFS= read -r forbidden; do
    ! rg -qF "${forbidden}" "${tmp}/refs.txt" || {
      echo "❌ vcluster lock references forbidden component '${forbidden}'" >&2
      exit 1
    }
  done < <(jq -r '.forbidden.imageSubstrings[]' "${lock}")
  while IFS= read -r floating; do
    ! rg -q ":${floating}@|:${floating}$" "${tmp}/refs.txt" || {
      echo "❌ vcluster lock references floating version '${floating}'" >&2
      exit 1
    }
  done < <(jq -r '.forbidden.floatingVersions[]' "${lock}")
  echo "✅ The vcluster lock pins pure-OSS components by digest with no floating version"
  ;;
vcluster-lock-negative)
  jq '.images.controlPlane = "ghcr.io/loft-sh/vcluster-pro:0.35.1@sha256:35faf06fbfce4a3802ca7e459998dc191aad06a3544bde1a46118a4edcdaef62"' nix/snapshots/entei-vcluster.json >"${tmp}/lock.json"
  jq -r '.images[]' "${tmp}/lock.json" >"${tmp}/refs.txt"
  rg -qF 'vcluster-pro' "${tmp}/refs.txt" || {
    echo "❌ the forbidden-component scan cannot see a Pro image" >&2
    exit 1
  }
  echo "✅ A Pro vcluster image is detectable by the lock guard"
  ;;
fixture-fence)
  # A fixture must never be readable as a roster without the explicit opt-in.
  ! env -u DIENE_PARITY_FIXTURES DIENE_PARITY_FIXTURES=false ./scripts/local/garden-render.sh all >/dev/null 2>&1 || {
    echo "❌ the renderer read fixtures without the explicit opt-in" >&2
    exit 1
  }
  echo "✅ Fixtures are fenced behind an explicit opt-in"
  ;;
presence)
  for required in sulfoxide/profiles.yaml sulfoxide/import.yaml schemas/sulfoxidemember.json nix/snapshots/entei-vcluster.json scripts/local/garden-render.sh scripts/local/garden-doctor.sh scripts/local/garden-installed-tuple.sh docs/developer/sulfoxide-parity.md; do
    [ ! -f "${required}" ] && echo "❌ required artifact '${required}' is missing" >&2 && exit 1
  done
  count="$(find sulfoxide/members -name '*.yaml' | wc -l | tr -d ' ')"
  [ "${count}" -lt 1 ] && echo "❌ no member definitions are present" >&2 && exit 1
  echo "✅ Parity artifacts are present (${count} sulfoxide-home members)"
  ;;
*)
  echo "❌ unsupported validation mode '${mode}'" >&2
  exit 1
  ;;
esac
