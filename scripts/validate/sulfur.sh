#!/usr/bin/env bash
# sulfur cert-manager engine — unit-tier testing pyramid (S30 / Q-I27).
#
# sulfur is a materialized chart PRODUCT: it inherits the helm-wrapper *shape*
# but not the probe obligation. Evidence is an ordinary testing pyramid with
# negative fixtures as normal tests. This script owns the unit tier
# (lint/render/schema/static conformance); the k3d integration tier lives in
# sulfur-k3d.sh.
set -euo pipefail

mode="${1:-}"
release="${RELEASE:-sulfur}"
namespace="${NAMESPACE:-sample}"
label_prefix="${LABEL_PREFIX:-atomi.cloud}"
repo_root="$(pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "${tmp}"' EXIT

[ -z "${mode}" ] && echo "❌ validation mode not set" >&2 && exit 1

# Collect the --values/-f overlays passed to a helm invocation so the identity
# layer is derived from the SAME merged values that will be rendered.
value_files() {
  local args=("$@") i=0 out=()
  while [ "$i" -lt "${#args[@]}" ]; do
    case "${args[$i]}" in
    --values | -f)
      i=$((i + 1))
      out+=("${args[$i]}")
      ;;
    esac
    i=$((i + 1))
  done
  [ "${#out[@]}" -gt 0 ] && printf '%s\n' "${out[@]}"
  return 0
}

# The supported render path: subchart values cannot call templates, so the LPSM
# identity labels are injected from a generated upstream.global.commonLabels layer
# derived from the single labelPrefix (+ serviceTree). Every template/lint command
# appends this layer; the validate.yaml guard fails rendering if it is missing.
identity_layer() {
  local vfiles=() layer
  mapfile -t vfiles < <(value_files "$@")
  layer="$(mktemp "${tmp}/identity-XXXXXX.yaml")"
  ./scripts/local/gen-identity-values.sh ${vfiles[@]+"${vfiles[@]}"} >"${layer}"
  printf '%s\n' "${layer}"
}

render() {
  local layer
  layer="$(identity_layer "$@")"
  helm template "${release}" chart --namespace "${namespace}" "$@" --values "${layer}"
}

lint() {
  local layer
  layer="$(identity_layer "$@")"
  helm lint chart --namespace "${namespace}" "$@" --values "${layer}"
}

# Render every committed values stack (base -> landscape -> cluster).
render_all() {
  render >/dev/null
  render --values chart/values.example.yaml >/dev/null
  render --values chart/values.example.yaml --values chart/values.lapras.yaml >/dev/null
}

assert_gateway_api_enabled() {
  local values_file="$1" cfg up
  cfg="$(yq -r '.config.enableGatewayAPI' "$values_file")"
  up="$(yq -r '.upstream.config.enableGatewayAPI' "$values_file")"
  [ "$cfg" = "true" ] && [ "$up" = "true" ]
}

assert_no_dead_feature_gate() {
  # ExperimentalGatewayAPISupport was removed in cert-manager v1.15; the
  # canonical knob is config.enableGatewayAPI. The dead flag must never appear.
  local values_file="$1"
  ! rg -q 'ExperimentalGatewayAPISupport' "$values_file"
}

case "${mode}" in
schema)
  lint >/dev/null
  lint --values chart/values.example.yaml >/dev/null
  lint --values chart/values.example.yaml --values chart/values.lapras.yaml >/dev/null
  ;;

schema-drift)
  ./scripts/local/generate-chart-schema.sh "${tmp}/values.schema.json" >/dev/null
  cmp chart/values.schema.json "${tmp}/values.schema.json"
  ;;

lint)
  lint
  lint --values chart/values.example.yaml
  lint --values chart/values.example.yaml --values chart/values.lapras.yaml
  ;;

render)
  render_all
  ;;

labels)
  # LPSM identity is stamped onto every rendered cert-manager resource via the
  # generated upstream.global.commonLabels layer (subchart values cannot call
  # templates). labelPrefix is the single configurable input; overriding it must
  # re-key the rendered labels (drop the default prefix).
  render --values chart/values.example.yaml --values chart/values.lapras.yaml >"${tmp}/rendered.yaml"
  yq eval-all -o=json '.' "${tmp}/rendered.yaml" |
    jq -s -e --arg p "${label_prefix}" \
      'map(select(.kind != null)) | length > 0 and all(.[]; (.metadata.labels[$p + "/service"] == "sulfur") and (.metadata.labels[$p + "/module"] == "certs") and (.metadata.labels[$p + "/layer"] == "1") and (.metadata.labels[$p + "/platform"] == "sample") and (.metadata.labels[$p + "/landscape"] == "example") and (.metadata.labels[$p + "/cluster"] == "lapras"))' >/dev/null
  # No static, independently editable mirror may remain: the committed values must
  # not hard-code upstream.global.commonLabels (labelPrefix is the only source).
  for vf in chart/values.yaml chart/values.example.yaml chart/values.lapras.yaml; do
    if [ "$(yq -r '.upstream.global.commonLabels // "absent"' "$vf")" != "absent" ]; then
      echo "❌ ${vf} still hard-codes upstream.global.commonLabels (labelPrefix must be the only source)" >&2
      exit 1
    fi
  done
  # Prefix-override render proof: overriding the single labelPrefix re-keys every
  # rendered identity label and removes the default prefix entirely.
  printf 'labelPrefix: example.dev\n' >"${tmp}/prefix.yaml"
  render --values chart/values.example.yaml --values chart/values.lapras.yaml --values "${tmp}/prefix.yaml" >"${tmp}/prefixed.yaml"
  yq eval-all -o=json '.' "${tmp}/prefixed.yaml" |
    jq -s -e 'map(select(.kind != null)) | length > 0 and all(.[]; (.metadata.labels["example.dev/service"] == "sulfur") and (.metadata.labels["example.dev/platform"] == "sample") and (.metadata.labels["atomi.cloud/service"] == null))' >/dev/null || {
    echo "❌ labelPrefix override did not re-key the rendered identity labels" >&2
    exit 1
  }
  ;;

identity)
  # Render-time LPSM guard (validate.yaml -> sulfur.validateServiceTree): platform
  # is namespace-sourced (must equal the release namespace) and the derived
  # commonLabels platform must mirror it. sulfur ships no resource of its own.
  # Positive: platform == namespace renders cleanly.
  render >/dev/null
  # Negative: a mismatched install namespace must fail Helm rendering.
  identity_ns_layer="$(identity_layer)"
  if helm template "${release}" chart --namespace other --values "${identity_ns_layer}" >/dev/null 2>&1; then
    echo "❌ render succeeded with serviceTree.platform != release namespace" >&2
    exit 1
  fi
  # Negative: rendering WITHOUT the generated identity layer must fail — the
  # commonLabels mirror guard makes the generated render path mandatory.
  if helm template "${release}" chart --namespace "${namespace}" >/dev/null 2>&1; then
    echo "❌ render succeeded without the generated identity layer" >&2
    exit 1
  fi
  ;;

reloader)
  # The supported Reloader opt-out is the three nullable upstream podAnnotations
  # (controller/webhook/cainjector); there is NO inert reloader.enabled toggle.
  for vf in chart/values.yaml chart/values.example.yaml chart/values.lapras.yaml; do
    if [ "$(yq -r '.reloader // "absent"' "$vf")" != "absent" ]; then
      echo "❌ ${vf} declares an inert 'reloader' flag (opt-out is the nullable upstream podAnnotations)" >&2
      exit 1
    fi
  done
  # Reloader opt-in is baked onto every long-running cert-manager workload
  # (controller/cainjector/webhook). The one-shot startupapicheck Job is excluded.
  render >"${tmp}/default.yaml"
  yq eval-all -o=json '.' "${tmp}/default.yaml" |
    jq -s -e 'map(select(.kind == "Deployment" or .kind == "StatefulSet" or .kind == "DaemonSet")) | length == 3 and all(.[]; .spec.template.metadata.annotations["reloader.stakater.com/auto"] == "true")' >/dev/null
  # Opt-out path: a values overlay nulling the upstream podAnnotations drops the
  # annotation from every workload.
  cat >"${tmp}/optout.yaml" <<'YAML'
upstream:
  podAnnotations:
    reloader.stakater.com/auto: null
  webhook:
    podAnnotations:
      reloader.stakater.com/auto: null
  cainjector:
    podAnnotations:
      reloader.stakater.com/auto: null
YAML
  render --values "${tmp}/optout.yaml" >"${tmp}/optout-rendered.yaml"
  yq eval-all -o=json '.' "${tmp}/optout-rendered.yaml" |
    jq -s -e 'map(select(.kind == "Deployment")) | all(.[]; .spec.template.metadata.annotations["reloader.stakater.com/auto"] == null)' >/dev/null
  ;;

rendered-manifests)
  # Q-G20 — inherited rendered-manifest validation stage:
  # helm template -> kubeconform (k8s schemas) -> kyverno apply VAP eval.
  # The six cert-manager CRD *definitions* are upstream-authoritative and skipped
  # (they cannot validate against themselves); every native resource is checked.
  render >"${tmp}/rendered.yaml"
  kubeconform -strict -summary -skip CustomResourceDefinition -schema-location default "${tmp}/rendered.yaml"
  yq eval-all 'select(.kind == "Deployment" or .kind == "StatefulSet" or .kind == "DaemonSet" or .kind == "Job" or .kind == "Service")' "${tmp}/rendered.yaml" >"${tmp}/vap-resources.yaml"
  kyverno apply policies/vap --resource "${tmp}/vap-resources.yaml" --detailed-results --remove-color
  # ONE wiring sabotage (Q-G20): a :latest workload image must redden the stage.
  sed 's|cert-manager-controller:v1.20.3|cert-manager-controller:latest|' "${tmp}/rendered.yaml" |
    yq eval-all 'select(.kind == "Deployment" or .kind == "Job")' >"${tmp}/sabotage.yaml"
  if kyverno apply policies/vap --resource "${tmp}/sabotage.yaml" --remove-color >/dev/null 2>&1; then
    echo "❌ :latest wiring sabotage was not caught" >&2
    exit 1
  fi
  ;;

sequential-minor)
  # Q-G22 — cert-manager sequential-minor gate (chart-repo CI check).
  # Positive steps: patch, same, and exactly-one-minor advances all pass.
  ./scripts/validate/sequential-minor.sh v1.20.3 v1.20.3 >/dev/null
  ./scripts/validate/sequential-minor.sh v1.20.3 v1.20.5 >/dev/null
  ./scripts/validate/sequential-minor.sh v1.20.0 v1.21.0 >/dev/null
  ./scripts/validate/sequential-minor.sh v1.19.0 v1.20.0 >/dev/null
  # Negative fixtures: a 2-minor skip and a major skip must both go red.
  if ./scripts/validate/sequential-minor.sh v1.20.3 v1.22.0 >/dev/null 2>&1; then
    echo "❌ sequential-minor gate accepted a 2-minor skip (v1.20 → v1.22)" >&2
    exit 1
  fi
  if ./scripts/validate/sequential-minor.sh v1.20.3 v2.0.0 >/dev/null 2>&1; then
    echo "❌ sequential-minor gate accepted a major skip" >&2
    exit 1
  fi
  ./scripts/validate/sequential-minor.sh --pin chart >/dev/null
  # Q-G22 CI-gate proof: the strict entrypoint must gate the ACTUAL chart
  # dependency against a base revision. Build a throwaway git repo so the gate
  # exercises its real base-ref derivation (git show <base>:chart/Chart.yaml).
  gate_repo="${tmp}/gate-repo"
  mkdir -p "${gate_repo}/chart"
  git -C "${gate_repo}" init -q
  git -C "${gate_repo}" config user.email ci@example.invalid
  git -C "${gate_repo}" config user.name ci
  write_gate_chart() {
    cat >"${gate_repo}/chart/Chart.yaml" <<YAML
apiVersion: v2
name: diene-sulfur
version: 0.1.0
dependencies:
  - name: cert-manager
    alias: upstream
    version: ${1}
    repository: https://charts.jetstack.io
YAML
  }
  write_gate_chart v1.20.3
  git -C "${gate_repo}" add -A
  git -C "${gate_repo}" commit -qm base
  gate_base="$(git -C "${gate_repo}" rev-parse HEAD)"
  # Positive: an exactly-one-minor dependency bump passes the CI gate.
  write_gate_chart v1.21.0
  (cd "${gate_repo}" && SULFUR_BASE_REF="${gate_base}" bash "${repo_root}/scripts/validate/sequential-minor.sh" --ci-gate chart) >/dev/null
  # Negative: a 2-minor dependency skip must turn the CI gate red.
  write_gate_chart v1.22.0
  if (cd "${gate_repo}" && SULFUR_BASE_REF="${gate_base}" bash "${repo_root}/scripts/validate/sequential-minor.sh" --ci-gate chart) >/dev/null 2>&1; then
    echo "❌ Q-G22 CI gate accepted a 2-minor chart-dependency skip (v1.20.3 → v1.22.0)" >&2
    exit 1
  fi
  # Negative: an unavailable comparison source must fail (never lax-pass).
  if (cd "${gate_repo}" && SULFUR_BASE_REF=deadbeefdeadbeefdeadbeefdeadbeefdeadbeef bash "${repo_root}/scripts/validate/sequential-minor.sh" --ci-gate chart) >/dev/null 2>&1; then
    echo "❌ Q-G22 CI gate passed with an unavailable base ref" >&2
    exit 1
  fi
  ;;

gateway-api)
  # Gateway API support is required (kgateway integration). The canonical knob
  # is upstream.config.enableGatewayAPI; config.enableGatewayAPI is the static
  # mirror. Both must be true and a disabled flag must be caught.
  assert_gateway_api_enabled chart/values.yaml || {
    echo "❌ Gateway API not enabled in base values" >&2
    exit 1
  }
  yq -o=yaml '.upstream.config.enableGatewayAPI = false | .config.enableGatewayAPI = false' chart/values.yaml >"${tmp}/no-gateway.yaml"
  if assert_gateway_api_enabled "${tmp}/no-gateway.yaml"; then
    echo "❌ gateway-api check missed a disabled flag" >&2
    exit 1
  fi
  ;;

no-dead-flag)
  # ExperimentalGatewayAPISupport is dead since v1.15; it must never appear.
  assert_no_dead_feature_gate chart/values.yaml || {
    echo "❌ dead ExperimentalGatewayAPISupport flag present" >&2
    exit 1
  }
  assert_no_dead_feature_gate chart/values.example.yaml
  assert_no_dead_feature_gate chart/values.lapras.yaml
  printf 'upstream:\n  featureGates: "ExperimentalGatewayAPISupport=true"\n' >"${tmp}/dead-flag.yaml"
  if assert_no_dead_feature_gate "${tmp}/dead-flag.yaml"; then
    echo "❌ dead-flag check missed ExperimentalGatewayAPISupport" >&2
    exit 1
  fi
  ;;

no-issuer)
  # Pure-passthrough invariant: sulfur owns the engine ONLY. Issuer/ClusterIssuer
  # *instances* live in zinc; sulfur ships neither (only the upstream CRD
  # definitions render). A synthesized Issuer template must be caught.
  if rg -q 'kind:[[:space:]]*(Cluster)?Issuer\b' chart/templates/; then
    echo "❌ sulfur ships an Issuer/ClusterIssuer template (issuers live in zinc)" >&2
    exit 1
  fi
  mkdir -p "${tmp}/chart/templates"
  cp -r chart/. "${tmp}/chart/"
  printf 'apiVersion: cert-manager.io/v1\nkind: ClusterIssuer\nmetadata:\n  name: forbidden\nspec:\n  selfSigned: {}\n' >"${tmp}/chart/templates/issuer-fixture.yaml"
  rg -q 'kind:[[:space:]]*(Cluster)?Issuer\b' "${tmp}/chart/templates/" || {
    echo "❌ boundary check missed a synthesized Issuer template" >&2
    exit 1
  }
  ;;

crds)
  # CRDs are installed by the engine chart (crds.enabled) and kept on uninstall
  # (crds.keep) so certificates survive. Disabling the flag drops every CRD.
  [ "$(yq -r '.upstream.crds.enabled' chart/values.yaml)" = "true" ] || {
    echo "❌ upstream.crds.enabled is not true" >&2
    exit 1
  }
  [ "$(yq -r '.upstream.crds.keep' chart/values.yaml)" = "true" ] || {
    echo "❌ upstream.crds.keep is not true" >&2
    exit 1
  }
  render >"${tmp}/with-crds.yaml"
  [ "$(rg -c '^kind: CustomResourceDefinition$' "${tmp}/with-crds.yaml")" -gt 0 ] || {
    echo "❌ no CRDs rendered with crds.enabled=true" >&2
    exit 1
  }
  # Negative fixture: crds.enabled=false must render zero CRD definitions.
  render --set upstream.crds.enabled=false >"${tmp}/no-crds.yaml"
  if rg -q '^kind: CustomResourceDefinition$' "${tmp}/no-crds.yaml"; then
    echo "❌ CRDs still rendered with crds.enabled=false" >&2
    exit 1
  fi
  ;;

publish-git)
  PUBLISH_MODE=git PUBLISH_DRY_RUN=true RELEASE_VERSION=v0.1.0 PUBLISH_OUTPUT_DIR="${tmp}/git" bash ./scripts/ci/publish.sh >/dev/null
  [ ! -s "${tmp}/git/diene-sulfur-0.1.0.tgz" ] && echo "❌ git chart package missing" >&2 && exit 1
  [ ! -s "${tmp}/git/index.yaml" ] && echo "❌ git chart index missing" >&2 && exit 1
  ;;

publish-oci)
  PUBLISH_MODE=oci PUBLISH_DRY_RUN=true RELEASE_VERSION=v0.1.0 PUBLISH_OUTPUT_DIR="${tmp}/oci" bash ./scripts/ci/publish.sh >/dev/null
  [ ! -s "${tmp}/oci/diene-sulfur-0.1.0.tgz" ] && echo "❌ OCI chart package missing" >&2 && exit 1
  rg -q '^oci://registry.example.invalid/charts$' "${tmp}/oci/oci-ref.txt"
  ;;

version)
  PUBLISH_MODE=git PUBLISH_DRY_RUN=true RELEASE_VERSION=v0.1.0 PUBLISH_OUTPUT_DIR="${tmp}/version" bash ./scripts/ci/publish.sh >/dev/null
  ;;

presence)
  test -s docs/developer/sulfur-baseline.md
  test -s chart/templates/_helpers.tpl
  test -s policies/vap/workload-baseline.yaml
  test -s policies/vap/service-baseline.yaml
  rg -q '^## Tokenization surface$' docs/developer/sulfur-baseline.md
  ;;

task-surface)
  # Regression for the public cluster Taskfile surface. `example:<landscape>:template`
  # must route through render-stacked.sh, generate the identity layer from the exact
  # base+landscape+cluster stack, and append it LAST — so the mandatory validate.yaml
  # guard passes and the generated LPSM identity labels reach the render. A Taskfile
  # edit that drops the identity layer (the reviewer's blocker) turns this red.
  command -v task >/dev/null || {
    echo "❌ 'task' runner unavailable for the Taskfile-surface regression" >&2
    exit 1
  }
  tree_before="$(git status --porcelain)"
  task example:lapras:template >"${tmp}/task-render.yaml" 2>"${tmp}/task-render.err" || {
    echo "❌ public 'example:lapras:template' task failed to render (identity layer missing?)" >&2
    cat "${tmp}/task-render.err" >&2
    exit 1
  }
  yq eval-all -o=json '.' "${tmp}/task-render.yaml" |
    jq -s -e --arg p "${label_prefix}" \
      'map(select(.kind != null)) | length > 0 and all(.[]; (.metadata.labels[$p + "/service"] == "sulfur") and (.metadata.labels[$p + "/platform"] == "sample") and (.metadata.labels[$p + "/landscape"] == "example") and (.metadata.labels[$p + "/cluster"] == "lapras"))' >/dev/null || {
    echo "❌ public template task render is missing the generated LPSM identity labels (identity layer not appended)" >&2
    exit 1
  }
  # The wrapper renders through a mktemp layer and must introduce no working-tree
  # change (no leaked temp identity layer, no dirtied committed files). Compared to a
  # pre-run snapshot so a legitimately dirty tree does not mask a real leak.
  [ "$(git status --porcelain)" != "${tree_before}" ] && echo "❌ public template task changed the working tree (temp layer not isolated)" >&2 && git status --porcelain >&2 && exit 1
  ;;

k3d-guard)
  # Non-live guard for the held k3d proof's isolation/ownership/collision logic, using
  # a fake k3d backend. Proves: (1) the isolated proof rejects preset identity
  # overrides and passes an explicit --kube-context; (2) create refuses a pre-existing
  # cluster/registry (collision) and claims ownership of exactly what it builds; and
  # (3) delete tears down ONLY owned resources (nothing when no ownership was claimed).
  fakebin="${tmp}/fakebin"
  mkdir -p "${fakebin}"
  cat >"${fakebin}/k3d" <<'FAKE'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"${FAKE_K3D_LOG:-/dev/null}"
case "${1:-} ${2:-}" in
"cluster list") cat "${FAKE_K3D_CLUSTERS:-/dev/null}" 2>/dev/null || true ;;
"registry list") cat "${FAKE_K3D_REGISTRIES:-/dev/null}" 2>/dev/null || true ;;
*) : ;;
esac
FAKE
  chmod +x "${fakebin}/k3d"
  marker="${tmp}/marker"

  # (1a) Override rejection: a preset identity var under path isolation must fail
  # closed at the guard, before any k3d/helm call.
  if PATH="${fakebin}:${PATH}" K3D_ISOLATE_BY_PATH=true K3D_CLUSTER_NAME=intruder \
    bash ./scripts/validate/sulfur-k3d.sh 2>"${tmp}/reject.err"; then
    echo "❌ isolated proof accepted a preset K3D_CLUSTER_NAME override" >&2
    exit 1
  fi
  rg -q 'must not be preset when K3D_ISOLATE_BY_PATH=true' "${tmp}/reject.err" || {
    echo "❌ isolated proof did not reject the preset identity override at the guard" >&2
    exit 1
  }

  # (1b) Explicit-context invariant: the held proof installs into the isolated cluster.
  rg -qF -- '--kube-context "k3d-${cluster_name}"' scripts/validate/sulfur-k3d.sh || {
    echo "❌ held k3d proof does not pass an explicit --kube-context to helm install" >&2
    exit 1
  }

  # (2a) Collision refusal (cluster): create must fail closed, write no marker, and
  # never issue a create.
  printf 'diene-sulfur-fake\n' >"${tmp}/clusters"
  : >"${tmp}/registries"
  : >"${tmp}/collide.log"
  rm -f "${marker}"
  if PATH="${fakebin}:${PATH}" FAKE_K3D_CLUSTERS="${tmp}/clusters" FAKE_K3D_REGISTRIES="${tmp}/registries" \
    FAKE_K3D_LOG="${tmp}/collide.log" K3D_CLUSTER_NAME=diene-sulfur-fake K3D_REGISTRY_NAME=diene-sulfur-registry-fake \
    K3D_REQUIRE_OWNERSHIP=true K3D_OWNERSHIP_MARKER="${marker}" \
    bash ./scripts/local/create-k3d-cluster.sh 2>/dev/null; then
    echo "❌ create adopted a pre-existing cluster under strict ownership" >&2
    exit 1
  fi
  [ -f "${marker}" ] && echo "❌ create claimed ownership despite refusing a collision" >&2 && exit 1
  rg -q 'cluster create' "${tmp}/collide.log" && echo "❌ create issued a k3d create despite a collision" >&2 && exit 1

  # (2b) Collision refusal (k3d-prefixed registry) must also fail closed.
  : >"${tmp}/clusters"
  printf 'k3d-diene-sulfur-registry-fake\n' >"${tmp}/registries"
  if PATH="${fakebin}:${PATH}" FAKE_K3D_CLUSTERS="${tmp}/clusters" FAKE_K3D_REGISTRIES="${tmp}/registries" \
    FAKE_K3D_LOG="${tmp}/collide.log" K3D_CLUSTER_NAME=diene-sulfur-fake K3D_REGISTRY_NAME=diene-sulfur-registry-fake \
    K3D_REQUIRE_OWNERSHIP=true K3D_OWNERSHIP_MARKER="${marker}" \
    bash ./scripts/local/create-k3d-cluster.sh 2>/dev/null; then
    echo "❌ create adopted a pre-existing (k3d-prefixed) registry under strict ownership" >&2
    exit 1
  fi

  # (2c) Clean create claims ownership of exactly what it built.
  : >"${tmp}/clusters"
  : >"${tmp}/registries"
  : >"${tmp}/create.log"
  PATH="${fakebin}:${PATH}" FAKE_K3D_CLUSTERS="${tmp}/clusters" FAKE_K3D_REGISTRIES="${tmp}/registries" \
    FAKE_K3D_LOG="${tmp}/create.log" K3D_CLUSTER_NAME=diene-sulfur-fake K3D_REGISTRY_NAME=diene-sulfur-registry-fake \
    K3D_REQUIRE_OWNERSHIP=true K3D_OWNERSHIP_MARKER="${marker}" \
    bash ./scripts/local/create-k3d-cluster.sh >/dev/null 2>&1
  { rg -qx 'cluster=diene-sulfur-fake' "${marker}" && rg -qx 'registry=diene-sulfur-registry-fake' "${marker}"; } || {
    echo "❌ create did not record ownership of the resources it built" >&2
    exit 1
  }
  rg -q 'cluster create' "${tmp}/create.log" || {
    echo "❌ clean create never issued a k3d create" >&2
    exit 1
  }

  # (3a) Owned cleanup: delete tears down exactly the owned cluster+registry.
  printf 'diene-sulfur-fake\n' >"${tmp}/clusters"
  printf 'k3d-diene-sulfur-registry-fake\n' >"${tmp}/registries"
  : >"${tmp}/delete.log"
  PATH="${fakebin}:${PATH}" FAKE_K3D_CLUSTERS="${tmp}/clusters" FAKE_K3D_REGISTRIES="${tmp}/registries" \
    FAKE_K3D_LOG="${tmp}/delete.log" K3D_REQUIRE_OWNERSHIP=true K3D_OWNERSHIP_MARKER="${marker}" \
    bash ./scripts/local/delete-k3d-cluster.sh >/dev/null 2>&1
  rg -q 'cluster delete diene-sulfur-fake' "${tmp}/delete.log" || {
    echo "❌ owned cleanup did not delete the owned cluster" >&2
    exit 1
  }
  rg -q 'registry delete diene-sulfur-registry-fake' "${tmp}/delete.log" || {
    echo "❌ owned cleanup did not delete the owned registry" >&2
    exit 1
  }

  # (3b) Unowned cleanup (no marker) must delete nothing.
  rm -f "${marker}"
  : >"${tmp}/noop.log"
  PATH="${fakebin}:${PATH}" FAKE_K3D_CLUSTERS="${tmp}/clusters" FAKE_K3D_REGISTRIES="${tmp}/registries" \
    FAKE_K3D_LOG="${tmp}/noop.log" K3D_REQUIRE_OWNERSHIP=true K3D_OWNERSHIP_MARKER="${marker}" \
    bash ./scripts/local/delete-k3d-cluster.sh >/dev/null 2>&1
  rg -q 'delete' "${tmp}/noop.log" && echo "❌ cleanup with no ownership marker deleted a resource" >&2 && exit 1
  ;;

*)
  echo "❌ unknown validation mode '${mode}'" >&2
  exit 1
  ;;
esac

echo "✅ sulfur ${mode} validation passed"
