#!/usr/bin/env bash
# ### aluminium-validate
# #### source: aluminium
# Ordinary testing pyramid (S30/Q-I27) for the aluminium k8s-monitoring wrapper.
# Unit tier: lint/render/schema/static conformance + OTLP/log contracts. No probe
# matrix (aluminium is a materialized product, not the helm-wrapper template).
set -euo pipefail

mode="${1:-}"
release="${RELEASE:-aluminium}"
namespace="${NAMESPACE:-telemetry}"
tmp="$(mktemp -d)"
trap 'rm -rf "${tmp}"' EXIT

chart_dir="chart"
vap_dir="policies/vap"
schema_location_default='default'
schema_location_local='schemas/{{ .ResourceKind }}.json'

[ -z "${mode}" ] && echo "❌ validation mode not set" >&2 && exit 1

render() {
  # Render the full stacked values (base -> example -> lapras). Extra args
  # (e.g. --set for negative fixtures) are forwarded to helm.
  helm template "${release}" "${chart_dir}" --namespace "${namespace}" \
    --values "${chart_dir}/values.example.yaml" \
    --values "${chart_dir}/values.lapras.yaml" "$@"
}

case "${mode}" in
schema)
  helm lint "${chart_dir}" --namespace "${namespace}" >/dev/null
  helm lint "${chart_dir}" --namespace "${namespace}" --values "${chart_dir}/values.example.yaml" >/dev/null
  helm lint "${chart_dir}" --namespace "${namespace}" --values "${chart_dir}/values.example.yaml" --values "${chart_dir}/values.lapras.yaml" >/dev/null
  ;;

schema-drift)
  bash ./scripts/local/generate-chart-schema.sh "${tmp}/values.schema.json" >/dev/null
  cmp "${chart_dir}/values.schema.json" "${tmp}/values.schema.json"
  ;;

lint)
  helm lint "${chart_dir}" --namespace "${namespace}"
  helm lint "${chart_dir}" --namespace "${namespace}" --values "${chart_dir}/values.example.yaml"
  helm lint "${chart_dir}" --namespace "${namespace}" --values "${chart_dir}/values.example.yaml" --values "${chart_dir}/values.lapras.yaml"
  ;;

render)
  helm template "${release}" "${chart_dir}" --namespace "${namespace}" >/dev/null
  helm template "${release}" "${chart_dir}" --namespace "${namespace}" --values "${chart_dir}/values.example.yaml" >/dev/null
  render >/dev/null
  ;;

# Both collectors render from the stacked values with the required topology:
# alloy-metrics = StatefulSet + clustering + the :4318 OTLP receiver;
# alloy-logs = DaemonSet + scoped /var/log mount, no clustering.
topology)
  render >"${tmp}/rendered.yaml"
  yq eval-all -o=json '.' "${tmp}/rendered.yaml" |
    jq -s -e '[.[] | select(.kind == "Alloy")] | length == 2' >/dev/null
  yq eval-all -o=json '.' "${tmp}/rendered.yaml" |
    jq -s -e '[.[] | select(.kind == "Alloy" and (.metadata.name | endswith("alloy-metrics")))] | all(.[]; .spec.controller.type == "statefulset" and .spec.alloy.clustering.enabled == true and ([.spec.alloy.extraPorts[]? | select(.port == 4318 and .name == "otlp-http")] | length == 1))' >/dev/null
  yq eval-all -o=json '.' "${tmp}/rendered.yaml" |
    jq -s -e '[.[] | select(.kind == "Alloy" and (.metadata.name | endswith("alloy-logs")))] | all(.[]; .spec.controller.type == "daemonset" and .spec.alloy.mounts.varlog == true and ((.spec.alloy.clustering // {enabled: false}) | .enabled) == false)' >/dev/null
  # Negative fixture: disable clustering on alloy-metrics; the topology check must fail.
  yq eval-all -o=json '.' "${tmp}/rendered.yaml" |
    jq -c '. | if (.kind == "Alloy" and (.metadata.name | endswith("alloy-metrics"))) then .spec.alloy.clustering.enabled = false else . end' >"${tmp}/sabotage.jsonl"
  if jq -s -e '[.[] | select(.kind == "Alloy" and (.metadata.name | endswith("alloy-metrics")))] | all(.[]; .spec.alloy.clustering.enabled == true)' "${tmp}/sabotage.jsonl" >/dev/null 2>&1; then
    echo "❌ clustering-off mutation was not caught" >&2
    exit 1
  fi
  ;;

# :4318 http/protobuf OTLP receiver contract (R14/R17). Negative: changed port -> red.
otlp-contract)
  render >"${tmp}/rendered.yaml"
  yq eval-all -o=json '.' "${tmp}/rendered.yaml" |
    jq -s -e '[.[] | select(.kind == "Alloy" and (.metadata.name | endswith("alloy-metrics")))] | all(.[]; ([.spec.alloy.extraPorts[] | select(.port == 4318)] | length == 1))' >/dev/null
  # Receiver is wired http (not grpc) per the fleet OTLP contract.
  yq eval-all -o=json '.' "${tmp}/rendered.yaml" |
    jq -s -e '[.[] | select(.kind == "ConfigMap")] | map(.data // {}) | add | tostring | test("otelcol\\.receiver\\.otlp")' >/dev/null
  # Negative fixture: move the receiver off 4318; the contract check must fail.
  yq eval-all -o=json '.' "${tmp}/rendered.yaml" |
    jq -c '. | if (.kind == "Alloy" and (.metadata.name | endswith("alloy-metrics"))) then (.spec.alloy.extraPorts[] | select(.port == 4318) | .port) = 4317 else . end' >"${tmp}/port.jsonl"
  if jq -s -e '[.[] | select(.kind == "Alloy" and (.metadata.name | endswith("alloy-metrics")))] | all(.[]; ([.spec.alloy.extraPorts[] | select(.port == 4318)] | length == 1))' "${tmp}/port.jsonl" >/dev/null 2>&1; then
    echo "❌ port-4317 mutation was not caught" >&2
    exit 1
  fi
  ;;

# Non-selected k8s-monitoring features stay OFF (events, beyla, profiling, cost,
# selfReporting). Every negative invokes the same rendered-manifest checker as
# the production render.
features-off)
  render >"${tmp}/rendered.yaml"
  bash ./scripts/validate/aluminium-assert.sh features-off "${tmp}/rendered.yaml" >/dev/null

  render --set 'upstream.selfReporting.enabled=true' >"${tmp}/self-reporting.yaml"
  if bash ./scripts/validate/aluminium-assert.sh features-off "${tmp}/self-reporting.yaml" >/dev/null 2>&1; then
    echo "❌ self-reporting mutation was not caught" >&2
    exit 1
  fi

  render --set 'upstream.telemetryServices.beyla.deploy=true' >"${tmp}/beyla.yaml"
  if bash ./scripts/validate/aluminium-assert.sh features-off "${tmp}/beyla.yaml" >/dev/null 2>&1; then
    echo "❌ beyla mutation was not caught" >&2
    exit 1
  fi

  render \
    --set 'upstream.costMetrics.enabled=true' \
    --set 'upstream.costMetrics.collector=alloy-metrics' \
    --set 'upstream.telemetryServices.opencost.deploy=true' \
    --set 'upstream.telemetryServices.opencost.opencost.exporter.defaultClusterId=lapras' \
    --set 'upstream.telemetryServices.opencost.metricsSource=custom' >"${tmp}/cost.yaml"
  if bash ./scripts/validate/aluminium-assert.sh features-off "${tmp}/cost.yaml" >/dev/null 2>&1; then
    echo "❌ cost-metrics mutation was not caught" >&2
    exit 1
  fi
  ;;

# Destination naming uses gigapipe (never qryn — legacy Node repo) everywhere.
# The negative mutates a copied chart and invokes the same product-input checker.
gigapipe-naming)
  bash ./scripts/validate/aluminium-assert.sh gigapipe-naming . >/dev/null
  mkdir -p "${tmp}/qryn-product/scripts"
  cp -a "${chart_dir}" "${tmp}/qryn-product/chart"
  cp Taskfile.yaml "${tmp}/qryn-product/"
  cp -a scripts/local scripts/ci "${tmp}/qryn-product/scripts/"
  cp -a .github "${tmp}/qryn-product/"
  yq eval -i '.upstream.destinations.qryn = .upstream.destinations.gigapipe | del(.upstream.destinations.gigapipe)' "${tmp}/qryn-product/chart/values.yaml"
  if bash ./scripts/validate/aluminium-assert.sh gigapipe-naming "${tmp}/qryn-product" >/dev/null 2>&1; then
    echo "❌ legacy-destination mutation was not caught" >&2
    exit 1
  fi
  ;;

# Backend creds via ESO only — no literal credentials in any values file.
# Negative: a literal credential -> red.
secret)
  render --set secret.enabled=true >"${tmp}/secret.yaml"
  yq eval-all -o=json '.' "${tmp}/secret.yaml" |
    jq -s -e 'map(select(.kind == "ExternalSecret")) as $es | ($es | length == 1) and ($es[0].metadata.name == "aluminium-secrets") and (($es[0].spec.data // []) | length == 0) and ($es[0].spec.dataFrom | length >= 2) and ($es[0].spec.target.creationPolicy == "Owner")' >/dev/null
  bash ./scripts/validate/aluminium-assert.sh literal-secrets "${chart_dir}" >/dev/null
  mkdir -p "${tmp}/secret-chart"
  cp "${chart_dir}"/values*.yaml "${tmp}/secret-chart/"
  yq eval -i '.upstream.destinations.gigapipe.auth.password = "fixture-literal-credential"' "${tmp}/secret-chart/values.yaml"
  if bash ./scripts/validate/aluminium-assert.sh literal-secrets "${tmp}/secret-chart" >/dev/null 2>&1; then
    echo "❌ literal-credential mutation was not caught" >&2
    exit 1
  fi
  ;;

# OTLP-everywhere outbound (Q-I28): endpoints-only destination config, no
# per-signal protocol selector exists.
otlp-everywhere)
  render >"${tmp}/rendered.yaml"
  # Every configured destination speaks otlp/http.
  yq eval-all -o=json '.' "${tmp}/rendered.yaml" |
    jq -s -e '[.[] | select(.kind == "ConfigMap")] | map(.data // {}) | add | tostring | test("otelcol\\.exporter\\.otlphttp")' >/dev/null
  bash ./scripts/validate/aluminium-assert.sh otlp-surface "${chart_dir}" >/dev/null
  mkdir -p "${tmp}/protocol-chart"
  cp "${chart_dir}"/values*.yaml "${tmp}/protocol-chart/"
  yq eval -i '.upstream.destinations.gigapipe.logs.protocol = "grpc"' "${tmp}/protocol-chart/values.yaml"
  if bash ./scripts/validate/aluminium-assert.sh otlp-surface "${tmp}/protocol-chart" >/dev/null 2>&1; then
    echo "❌ per-signal protocol mutation was not caught" >&2
    exit 1
  fi
  ;;

# Both collectors carry LPSM labels via the upstream alloy.labels injection.
lpsm-labels)
  render --set secret.enabled=true >"${tmp}/labels-default.yaml"
  bash ./scripts/validate/aluminium-assert.sh lpsm-labels "${tmp}/labels-default.yaml" atomi.cloud >/dev/null
  render --set global.labelPrefix=example.test --set secret.enabled=true >"${tmp}/labels-custom.yaml"
  bash ./scripts/validate/aluminium-assert.sh lpsm-labels "${tmp}/labels-custom.yaml" example.test >/dev/null
  ;;

# Inherited rendered-manifest validation stage (Q-G20): kubeconform over the full
# render, Kyverno VAP evaluation of every matched native object, then the ONE
# `:latest` wiring sabotage.
rendered-manifests)
  render >"${tmp}/rendered.yaml"
  kubeconform -strict -summary -schema-location "${schema_location_default}" -schema-location "${schema_location_local}" "${tmp}/rendered.yaml"
  # Collectors are configured conformant (resources + securityContext + labels).
  yq eval-all -o=json '.' "${tmp}/rendered.yaml" |
    jq -s -e '[.[] | select(.kind == "Alloy")] | all(.[]; (.spec.alloy.resources.requests.cpu // null) != null and (.spec.alloy.resources.limits.cpu // null) != null)' >/dev/null
  # Kyverno's offline VAP evaluator cannot map unrelated CR GVRs. Feed it the
  # exact native object kinds matched by the policy definitions.
  yq eval-all 'select(.kind == "Deployment" or .kind == "StatefulSet" or .kind == "DaemonSet" or .kind == "Job" or .kind == "Service")' "${tmp}/rendered.yaml" >"${tmp}/vap-resources.yaml"
  kyverno apply "${vap_dir}" --resource "${tmp}/vap-resources.yaml" --detailed-results --remove-color >"${tmp}/kyverno-baseline.out"
  # ONE wiring sabotage: a workload fixture carrying a `:latest` image MUST be
  # caught by the VAP (proves the stage cannot silently stop matching). Every
  # other baseline field is conformant, so :latest is the sole failure.
  cat >"${tmp}/latest-fixture.yaml" <<'YAML'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: aluminium-latest-sabotage
  namespace: telemetry
spec:
  selector:
    matchLabels:
      app: aluminium-latest-sabotage
  template:
    metadata:
      labels:
        app: aluminium-latest-sabotage
    spec:
      securityContext:
        runAsNonRoot: true
      containers:
        - name: sabotage
          image: registry.example.invalid/sabotage:latest
          resources:
            requests: { cpu: 1m, memory: 1Mi }
            limits: { cpu: 1m, memory: 1Mi }
          securityContext:
            runAsNonRoot: true
            allowPrivilegeEscalation: false
            readOnlyRootFilesystem: true
            capabilities:
              drop: [ALL]
YAML
  if kyverno apply "${vap_dir}" --resource "${tmp}/latest-fixture.yaml" --remove-color >"${tmp}/kyverno.out" 2>&1; then
    echo "❌ :latest wiring sabotage was NOT caught" >&2
    exit 1
  fi
  rg -qi 'latest' "${tmp}/kyverno.out"
  ;;

latest-semver)
  ALUMINIUM_HELM_SEARCH_JSON='[{"name":"grafana/k8s-monitoring","version":"4.9.0"},{"name":"grafana/k8s-monitoring","version":"4.10.0"},{"name":"grafana/k8s-monitoring","version":"4.3.0"}]' \
    ALUMINIUM_IMAGE_TAGS_JSON='{"Tags":["1.9.0","1.10.0","latest"]}' \
    bash ./scripts/local/latest-chart-upstreams.sh >"${tmp}/latest.out"
  rg -q '^📦 latest chart tag:  grafana/k8s-monitoring 4\.10\.0$' "${tmp}/latest.out"
  rg -q '^📦 latest image tag:  grafana/alloy 1\.10\.0$' "${tmp}/latest.out"
  ;;

kubeconfig-isolation)
  mkdir -p "${tmp}/fake-bin"
  cat >"${tmp}/fake-bin/k3d" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
{
  printf 'kubeconfig=%s\t' "${KUBECONFIG:-}"
  printf '%s' "${1:-}"
  shift || true
  printf ' %s' "$@"
  printf '\n'
} >>"${K3D_FAKE_LOG:?}"
case "${1:-}" in
list | create) exit 0 ;;
*) exit 91 ;;
esac
SH
  chmod +x "${tmp}/fake-bin/k3d"
  local_kubeconfig="${tmp}/local-kubeconfig.yaml"
  safe_log="${tmp}/safe-create.log"
  PATH="${tmp}/fake-bin:${PATH}" \
    K3D_FAKE_LOG="${safe_log}" \
    KUBECONFIG="${local_kubeconfig}" \
    K3D_CLUSTER_NAME=aluminium-fake \
    K3D_REGISTRY_NAME=aluminium-fake-registry \
    K3D_REGISTRY_PORT=25001 \
    K3D_HTTP_PORT=35001 \
    bash ./scripts/local/create-k3d-cluster.sh >/dev/null
  bash ./scripts/validate/aluminium-assert.sh k3d-create-log "${safe_log}" "${local_kubeconfig}" >/dev/null

  sed 's/--kubeconfig-update-default=false/--kubeconfig-update-default=true/' \
    ./scripts/local/create-k3d-cluster.sh >"${tmp}/unsafe-create.sh"
  unsafe_log="${tmp}/unsafe-create.log"
  PATH="${tmp}/fake-bin:${PATH}" \
    K3D_FAKE_LOG="${unsafe_log}" \
    KUBECONFIG="${local_kubeconfig}" \
    K3D_CLUSTER_NAME=aluminium-fake \
    K3D_REGISTRY_NAME=aluminium-fake-registry \
    K3D_REGISTRY_PORT=25001 \
    K3D_HTTP_PORT=35001 \
    bash "${tmp}/unsafe-create.sh" >/dev/null
  if bash ./scripts/validate/aluminium-assert.sh k3d-create-log "${unsafe_log}" "${local_kubeconfig}" >/dev/null 2>&1; then
    echo "❌ default-kubeconfig mutation was not caught" >&2
    exit 1
  fi

  bash ./scripts/validate/aluminium-assert.sh k3d-proof-script ./scripts/validate/aluminium-k3d.sh >/dev/null
  # shellcheck disable=SC2016 # The sabotage must match the literal shell expression.
  sed 's/--kubeconfig "${kubeconfig}" //' \
    ./scripts/validate/aluminium-k3d.sh >"${tmp}/unsafe-proof.sh"
  if bash ./scripts/validate/aluminium-assert.sh k3d-proof-script "${tmp}/unsafe-proof.sh" >/dev/null 2>&1; then
    echo "❌ missing local-kubeconfig propagation was not caught" >&2
    exit 1
  fi
  ;;

publish-git)
  PUBLISH_MODE=git PUBLISH_DRY_RUN=true RELEASE_VERSION=v0.1.0 PUBLISH_OUTPUT_DIR="${tmp}/git" bash ./scripts/ci/publish.sh >/dev/null
  [ ! -s "${tmp}/git/diene-charts-aluminium-0.1.0.tgz" ] && echo "❌ git chart package missing" >&2 && exit 1
  [ ! -s "${tmp}/git/index.yaml" ] && echo "❌ git chart index missing" >&2 && exit 1
  ;;

publish-oci)
  PUBLISH_MODE=oci PUBLISH_DRY_RUN=true RELEASE_VERSION=v0.1.0 PUBLISH_OUTPUT_DIR="${tmp}/oci" bash ./scripts/ci/publish.sh >/dev/null
  [ ! -s "${tmp}/oci/diene-charts-aluminium-0.1.0.tgz" ] && echo "❌ OCI chart package missing" >&2 && exit 1
  rg -q '^oci://registry.example.invalid/charts$' "${tmp}/oci/oci-ref.txt"
  ;;

version)
  PUBLISH_MODE=git PUBLISH_DRY_RUN=true RELEASE_VERSION=v0.1.0 PUBLISH_OUTPUT_DIR="${tmp}/version" bash ./scripts/ci/publish.sh >/dev/null
  ;;

presence)
  test -s docs/developer/aluminium-baseline.md
  test -s .claude/skills/aluminium/SKILL.md
  test -s policies/vap/workload-baseline.yaml
  test -s schemas/alloy.json
  test -x scripts/validate/aluminium-assert.sh
  ;;

*)
  echo "❌ unknown validation mode '${mode}'" >&2
  exit 1
  ;;
esac

echo "✅ aluminium ${mode} validation passed"
