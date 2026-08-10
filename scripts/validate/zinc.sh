#!/usr/bin/env bash
# Zinc unit-tier validation (materialized cert-manager issuer chart — S30, no probe
# matrix). One mode per independently invoked mechanism; the CI orchestrator calls
# them in order. Positive assertion and its negative fixture live together in each
# mode.
set -euo pipefail

mode="${1:-}"
release="${RELEASE:-zinc}"
namespace="${NAMESPACE:-cert-manager}"
base_overlay="chart/values.example.yaml"
prod_url="https://acme-v02.api.letsencrypt.org/directory"
staging_url="https://acme-staging-v02.api.letsencrypt.org/directory"
# The explicit five-landscape LE-directory map (Q-I33, amended): production on
# pikachu/raichu/amphoros; staging on pichu/lapras.
map_landscapes=(pikachu raichu amphoros pichu lapras)
map_directory() {
  case "$1" in
  pikachu | raichu | amphoros) echo production ;;
  pichu | lapras) echo staging ;;
  *)
    echo "❌ landscape $1 is not in the LE-directory map" >&2
    exit 1
    ;;
  esac
}
all_overlays=(example pikachu raichu amphoros pichu lapras entei)
tmp="$(mktemp -d)"
trap 'rm -rf "${tmp}"' EXIT

[ -z "${mode}" ] && echo "❌ validation mode not set" >&2 && exit 1

render() {
  # render <output> [overlay-file ...]
  local out="$1"
  shift
  local args=()
  local o
  for o in "$@"; do args+=(--values "${o}"); done
  helm template "${release}" chart --namespace "${namespace}" "${args[@]}" >"${out}"
}

case "${mode}" in
schema)
  helm lint chart --namespace "${namespace}" >/dev/null
  helm lint chart --namespace "${namespace}" --values "${base_overlay}" >/dev/null
  ;;
schema-negative)
  yq '.serviceTree.layer = "notnumeric"' chart/values.yaml >"${tmp}/invalid-values.yaml"
  if helm lint chart --namespace "${namespace}" --values "${tmp}/invalid-values.yaml" >"${tmp}/schema.stdout" 2>"${tmp}/schema.stderr"; then
    echo "❌ non-numeric layer passed Helm schema validation" >&2
    exit 1
  fi
  rg -qi 'layer|pattern|does not match' "${tmp}/schema.stdout" "${tmp}/schema.stderr"
  ;;
schema-drift)
  bash ./scripts/local/generate-chart-schema.sh "${tmp}/values.schema.json" >/dev/null
  cmp chart/values.schema.json "${tmp}/values.schema.json"
  ;;
lint)
  helm lint chart --namespace "${namespace}"
  for ls in "${all_overlays[@]}"; do
    echo "🔎 linting ${ls} overlay"
    helm lint chart --namespace "${namespace}" --values "chart/values.${ls}.yaml"
  done
  ;;
render)
  # Every rendered object name must be a valid RFC-1123 subdomain.
  for ls in "${all_overlays[@]}"; do
    render "${tmp}/render.yaml" "chart/values.${ls}.yaml"
    yq eval-all -o=json '.' "${tmp}/render.yaml" | jq -se '
      def dnssubdomain: test("^[a-z0-9]([-a-z0-9.]*[a-z0-9])?$");
      (map(select(type == "object" and has("kind")))) as $r
      | ($r | length) >= 1
        and (all($r[]; ((.metadata.name // "") | dnssubdomain)))
    ' >/dev/null || {
      echo "❌ rendered a non-RFC-1123 object name in the ${ls} overlay" >&2
      exit 1
    }
  done
  ;;
labels)
  # serviceTree.platform must never be a value; the slots must be consistent.
  yq -e '.serviceTree | has("platform") | not' chart/values.yaml >/dev/null
  render "${tmp}/rendered.yaml" chart/values.pikachu.yaml
  yq eval-all -o=json '.' "${tmp}/rendered.yaml" | jq --arg ns "${namespace}" -se '
    def lpsm($prefix; $namespace):
      (.[$prefix + "/platform"] == $namespace)
      and (.[$prefix + "/service"] == "zinc")
      and (.[$prefix + "/module"] == "issuer")
      and (.[$prefix + "/layer"] == "1")
      and (.[$prefix + "/landscape"] == "pikachu");
    (map(select(type == "object" and has("kind")))) as $resources
    | ($resources | map(select(.kind == "ClusterIssuer"))) as $issuers
    | ($resources | map(select(.kind == "ExternalSecret"))) as $secrets
    | ($issuers | length) == 1
      and ($secrets | length) == 1
      and (all($issuers[]; .metadata.labels | lpsm("atomi.cloud"; $ns)))
      and (all($issuers[]; .metadata.annotations | lpsm("atomi.cloud"; $ns)))
      and (all($secrets[]; .metadata.labels | lpsm("atomi.cloud"; $ns)))
      and (all($secrets[]; .metadata.annotations | lpsm("atomi.cloud"; $ns)))
  ' >/dev/null
  # Namespace change moves the platform label (platform is namespace-sourced).
  helm template "${release}" chart --namespace tenant --values chart/values.pikachu.yaml >"${tmp}/ns.yaml"
  yq eval-all -o=json '.' "${tmp}/ns.yaml" | jq -se '
    (map(select(type == "object" and .kind == "ClusterIssuer"))[0]) as $ci
    | $ci.metadata.labels["atomi.cloud/platform"] == "tenant"
      and $ci.metadata.annotations["atomi.cloud/platform"] == "tenant"
  ' >/dev/null
  # labelPrefix override reprefixes every key and leaves no atomi.cloud key.
  helm template "${release}" chart --namespace tenant --values chart/values.pikachu.yaml --set labelPrefix=example.dev >"${tmp}/override.yaml"
  yq eval-all -o=json '.' "${tmp}/override.yaml" | jq -se '
    def lpsm:
      (.["example.dev/platform"] == "tenant")
      and (.["example.dev/service"] == "zinc")
      and (.["example.dev/module"] == "issuer")
      and (.["example.dev/layer"] == "1")
      and (.["example.dev/landscape"] == "pikachu");
    (map(select(type == "object" and .kind == "ClusterIssuer"))[0]) as $ci
    | ($ci.metadata.labels | lpsm)
      and ($ci.metadata.annotations | lpsm)
      and ([$ci.metadata.labels, $ci.metadata.annotations] | map(to_entries[]) | map(select(.key | startswith("atomi.cloud/"))) | length) == 0
  ' >/dev/null
  # A forbidden platform value is rejected at render time.
  if helm template "${release}" chart --namespace tenant --values chart/values.pikachu.yaml --set serviceTree.platform=wrong >/dev/null 2>&1; then
    echo "❌ a forbidden serviceTree.platform value was accepted" >&2
    exit 1
  fi
  ;;
le-directory-map)
  # The explicit five-landscape map: production on pikachu/raichu/amphoros,
  # staging on pichu/lapras.
  server_of() {
    yq eval-all -o=json '.' "$1" | jq -sr '[.[] | select(type == "object" and .kind == "ClusterIssuer")][0].spec.acme.server'
  }
  for ls in "${map_landscapes[@]}"; do
    render "${tmp}/${ls}.yaml" "chart/values.${ls}.yaml"
    want="$(map_directory "${ls}")"
    got="$(server_of "${tmp}/${ls}.yaml")"
    case "${want}" in
    production) expect="${prod_url}" ;;
    staging) expect="${staging_url}" ;;
    esac
    if [ "${got}" != "${expect}" ]; then
      echo "❌ ${ls} maps to ${got}, expected the ${want} directory ${expect}" >&2
      exit 1
    fi
  done
  # Negative: a production-map landscape pointed at the staging directory must be
  # observably off-map (the assertion has teeth).
  helm template "${release}" chart --namespace "${namespace}" --values chart/values.pikachu.yaml \
    --set issuer.refs[0].directory=staging >"${tmp}/off-map.yaml"
  if [ "$(server_of "${tmp}/off-map.yaml")" = "${prod_url}" ]; then
    echo "❌ pikachu pointed at staging still resolved the production directory; map gate has no teeth" >&2
    exit 1
  fi
  ;;
issuer-cardinality)
  # Exactly ONE issuer definition template (no second hand-authored issuer).
  issuer_template_files="$(rg -l 'kind:\s*(Cluster)?Issuer' chart/templates/ | wc -l)"
  [ "${issuer_template_files}" -ne 1 ] && echo "❌ expected exactly one issuer template, found ${issuer_template_files}" >&2 && exit 1
  count_issuers() {
    yq eval-all -o=json '.' "$1" | jq -s '[.[] | select(type == "object" and (.kind == "Issuer" or .kind == "ClusterIssuer"))] | length'
  }
  # Registered clusters instantiate exactly one; ENTEI instantiates the pair.
  for ls in "${map_landscapes[@]}"; do
    render "${tmp}/${ls}.yaml" "chart/values.${ls}.yaml"
    [ "$(count_issuers "${tmp}/${ls}.yaml")" -ne 1 ] && echo "❌ ${ls} did not instantiate exactly one ClusterIssuer" >&2 && exit 1
    # No namespaced Issuer variant — every issuer is cluster-scoped.
    if yq eval-all -o=json '.' "${tmp}/${ls}.yaml" | jq -se 'any(.[]; type == "object" and .kind == "Issuer")' >/dev/null 2>&1; then
      echo "❌ ${ls} rendered a namespaced Issuer variant" >&2
      exit 1
    fi
  done
  render "${tmp}/entei.yaml" chart/values.entei.yaml
  [ "$(count_issuers "${tmp}/entei.yaml")" -ne 2 ] && echo "❌ ENTEI did not instantiate the staging+production pair" >&2 && exit 1
  # Negative: a second hand-authored issuer template reddens the single-source gate.
  cat >chart/templates/zz-issuer-variant-fixture.yaml <<'FIXTURE'
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: zinc-handauthored-variant
spec:
  selfSigned: {}
FIXTURE
  trap 'rm -f chart/templates/zz-issuer-variant-fixture.yaml; rm -rf "${tmp}"' EXIT
  if [ "$(rg -l 'kind:\s*(Cluster)?Issuer' chart/templates/ | wc -l)" -eq 1 ]; then
    echo "❌ issuer-cardinality negative fixture did not add a second issuer template" >&2
    exit 1
  fi
  rm -f chart/templates/zz-issuer-variant-fixture.yaml
  trap 'rm -rf "${tmp}"' EXIT
  ;;
entei-overlay)
  render "${tmp}/entei.yaml" chart/values.entei.yaml
  # Both stable refs render with the intended ACME directories and the
  # hosted-development zone solver restriction.
  yq eval-all -o=json '.' "${tmp}/entei.yaml" | jq -se --arg prod "${prod_url}" --arg staging "${staging_url}" '
    (map(select(type == "object" and .kind == "ClusterIssuer"))) as $ci
    | ($ci | map({key: .metadata.name, value: .spec.acme.server}) | from_entries) as $servers
    | ($ci | length) == 2
      and ($servers["zinc-letsencrypt-staging"] == $staging)
      and ($servers["zinc-letsencrypt-production"] == $prod)
      and (all($ci[]; (.spec.acme.solvers[0].dns01.cloudflare.apiTokenSecretRef.name != null)))
      and (all($ci[]; (.spec.acme.solvers[0].selector.dnsZones | index("dev.atomi.cloud")) != null))
  ' >/dev/null
  # Negative: dropping the hosted-zone restriction reddens the restriction check.
  helm template "${release}" chart --namespace "${namespace}" --values chart/values.entei.yaml \
    --set-json 'issuer.solver.dnsZones=[]' >"${tmp}/no-zone.yaml"
  if yq eval-all -o=json '.' "${tmp}/no-zone.yaml" | jq -se '
    map(select(type == "object" and .kind == "ClusterIssuer"))
    | all(.[]; (.spec.acme.solvers[0].selector.dnsZones | index("dev.atomi.cloud")) != null)
  ' >/dev/null 2>&1; then
    echo "❌ omitting the hosted-zone restriction did not red the ENTEI solver-restriction gate" >&2
    exit 1
  fi
  # Negative: the staging ref resolving to the production directory reddens the
  # issuance-class split.
  helm template "${release}" chart --namespace "${namespace}" --values chart/values.entei.yaml \
    --set issuer.refs[0].directory=production >"${tmp}/swapped.yaml"
  if yq eval-all -o=json '.' "${tmp}/swapped.yaml" | jq -se --arg staging "${staging_url}" '
    (map(select(type == "object" and .kind == "ClusterIssuer")) | map({key: .metadata.name, value: .spec.acme.server}) | from_entries) as $servers
    | $servers["zinc-letsencrypt-staging"] == $staging
  ' >/dev/null 2>&1; then
    echo "❌ the ENTEI staging ref resolving to production was not detected" >&2
    exit 1
  fi
  ;;
no-certificate)
  # Zinc renders zero Certificate objects across every overlay.
  cert_count() {
    yq eval-all -o=json '.' "$1" | jq -s '[.[] | select(type == "object" and .kind == "Certificate")] | length'
  }
  for ls in "${all_overlays[@]}"; do
    render "${tmp}/${ls}.yaml" "chart/values.${ls}.yaml"
    [ "$(cert_count "${tmp}/${ls}.yaml")" -ne 0 ] && echo "❌ ${ls} rendered a Certificate; dotted names require materializer-owned exact intents" >&2 && exit 1
  done
  # Negative: a chart-authored (wildcard) Certificate reddens the no-Certificate gate.
  cat >chart/templates/zz-certificate-fixture.yaml <<'FIXTURE'
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: zinc-wildcard-fixture
spec:
  secretName: zinc-wildcard-tls
  dnsNames:
    - '*.eevee.dev.atomi.cloud'
  issuerRef:
    name: zinc-letsencrypt
    kind: ClusterIssuer
FIXTURE
  trap 'rm -f chart/templates/zz-certificate-fixture.yaml; rm -rf "${tmp}"' EXIT
  render "${tmp}/fixture.yaml" chart/values.entei.yaml
  if [ "$(cert_count "${tmp}/fixture.yaml")" -eq 0 ]; then
    echo "❌ no-Certificate negative fixture did not surface a Certificate" >&2
    exit 1
  fi
  rm -f chart/templates/zz-certificate-fixture.yaml
  trap 'rm -rf "${tmp}"' EXIT
  ;;
credential-literal)
  # The Cloudflare token is referenced via a Secret ref only; nothing inline.
  for vf in chart/values.yaml chart/values.entei.yaml; do
    if yq -o=json '.' "${vf}" | rg -q '"apiToken"\s*:|"apiKey"\s*:'; then
      echo "❌ an inline Cloudflare token/key literal is present in ${vf}" >&2
      exit 1
    fi
  done
  render "${tmp}/render.yaml" chart/values.pikachu.yaml
  rg -q 'apiTokenSecretRef' "${tmp}/render.yaml" || {
    echo "❌ rendered solver does not reference the token via apiTokenSecretRef" >&2
    exit 1
  }
  if rg -q '^\s*apiToken:\s*\S' "${tmp}/render.yaml"; then
    echo "❌ rendered a bare inline apiToken value" >&2
    exit 1
  fi
  # Negative: an inline token in a wrapper template reddens the bare-token grep.
  cat >chart/templates/zz-inline-token-fixture.yaml <<'FIXTURE'
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: zinc-inline-token-fixture
spec:
  acme:
    server: https://acme-staging-v02.api.letsencrypt.org/directory
    solvers:
      - dns01:
          cloudflare:
            apiToken: cf-literal-token-should-be-rejected
FIXTURE
  trap 'rm -f chart/templates/zz-inline-token-fixture.yaml; rm -rf "${tmp}"' EXIT
  render "${tmp}/dirty.yaml" chart/values.pikachu.yaml
  if ! rg -q '^\s*apiToken:\s*\S' "${tmp}/dirty.yaml"; then
    echo "❌ credential-literal negative fixture did not inject an inline token; gate is not exercised" >&2
    exit 1
  fi
  rm -f chart/templates/zz-inline-token-fixture.yaml
  trap 'rm -rf "${tmp}"' EXIT
  ;;
rendered-manifests)
  # Inherited Q-G20 stage: helm template -> kubeconform -> Kyverno VAP eval. VAP
  # evaluation is vacuous for this workload-free chart (no workload/Service
  # targets), but render + kubeconform still run on every stack.
  for ls in example entei; do
    render "${tmp}/${ls}.yaml" "chart/values.${ls}.yaml"
    kubeconform -strict -summary -ignore-missing-schemas "${tmp}/${ls}.yaml"
    yq eval-all 'select(.kind == "Deployment" or .kind == "StatefulSet" or .kind == "DaemonSet" or .kind == "Job" or .kind == "Service")' "${tmp}/${ls}.yaml" >"${tmp}/${ls}-vap.yaml"
    if [ -s "${tmp}/${ls}-vap.yaml" ]; then
      kyverno apply policies/vap --resource "${tmp}/${ls}-vap.yaml" --detailed-results --remove-color
    else
      echo "ℹ️  ${ls}: no workload/Service targets; VAP evaluation is vacuous (render + kubeconform ran)"
    fi
  done
  ;;
vap-sabotage)
  # The ONE Q-G20 wiring sabotage: a schema-invalid rendered object reddens the
  # rendered-manifest stage (kubeconform catches the core-object schema break).
  cat >chart/templates/zz-vap-sabotage.yaml <<'FIXTURE'
apiVersion: v1
kind: Service
metadata:
  name: zinc-vap-sabotage
spec:
  ports:
    - port: not-an-integer
      targetPort: 80
FIXTURE
  trap 'rm -f chart/templates/zz-vap-sabotage.yaml; rm -rf "${tmp}"' EXIT
  render "${tmp}/rendered.yaml" chart/values.pikachu.yaml
  if kubeconform -strict -summary -ignore-missing-schemas "${tmp}/rendered.yaml" >/dev/null 2>&1; then
    echo "❌ schema-invalid rendered object was not caught by the rendered-manifest stage" >&2
    exit 1
  fi
  rm -f chart/templates/zz-vap-sabotage.yaml
  trap 'rm -rf "${tmp}"' EXIT
  ;;
publish-git)
  PUBLISH_MODE=git PUBLISH_DRY_RUN=true RELEASE_VERSION=v0.1.0 PUBLISH_OUTPUT_DIR="${tmp}/git" bash ./scripts/ci/publish.sh >/dev/null
  [ ! -s "${tmp}/git/diene-zinc-0.1.0.tgz" ] && echo "❌ git chart package missing" >&2 && exit 1
  [ ! -s "${tmp}/git/index.yaml" ] && echo "❌ git chart index missing" >&2 && exit 1
  ;;
publish-oci)
  PUBLISH_MODE=oci PUBLISH_DRY_RUN=true RELEASE_VERSION=v0.1.0 PUBLISH_OUTPUT_DIR="${tmp}/oci" bash ./scripts/ci/publish.sh >/dev/null
  [ ! -s "${tmp}/oci/diene-zinc-0.1.0.tgz" ] && echo "❌ OCI chart package missing" >&2 && exit 1
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
  test -s docs/developer/zinc-baseline.md
  test -s chart/templates/clusterissuer.yaml
  test -s chart/templates/externalsecret.yaml
  test -s chart/values.schema.json
  test -s policies/vap/workload-baseline.yaml
  test -s policies/vap/service-baseline.yaml
  test -x scripts/validate/zinc-k3d.sh
  for ls in pikachu raichu amphoros pichu lapras entei; do
    test -s "chart/values.${ls}.yaml"
  done
  ;;
*)
  echo "❌ unknown validation mode '${mode}'" >&2
  exit 1
  ;;
esac

echo "✅ Zinc ${mode} validation passed"
