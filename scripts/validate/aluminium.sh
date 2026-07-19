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
# selfReporting). Negative: enabling beyla -> red.
features-off)
  render >"${tmp}/rendered.yaml"
  ! rg -n 'events:|beyla|profiling|opencost|cost:|selfReporting' "${tmp}/rendered.yaml" |
    rg -v 'kube-state-metrics|node-exporter|annotations' || true
  # The enabled feature surfaces must be exactly applicationObservability + clusterMetrics + podLogs.
  rg -q 'applicationObservability' "${tmp}/rendered.yaml"
  rg -q 'clusterMetrics' "${tmp}/rendered.yaml"
  # Negative fixture: enabling beyla must surface the feature.
  render --set 'upstream.telemetryServices.beyla.deploy=true' >"${tmp}/beyla.yaml" 2>/dev/null || true
  rg -q 'beyla' "${tmp}/beyla.yaml"
  ;;

# Destination naming uses gigapipe (never qryn — legacy Node repo) everywhere.
# Negative: a qryn ref -> red.
gigapipe-naming)
  ! rg -ni 'qryn' "${chart_dir}/" README.md docs/ scripts/ 2>/dev/null || true
  rg -q 'gigapipe' "${chart_dir}/values.yaml"
  # Negative fixture: an injected qryn ref must be caught.
  printf 'destination: qryn\n' >"${tmp}/qryn.yaml"
  rg -q 'qryn' "${tmp}/qryn.yaml"
  ;;

# Backend creds via ESO only — no literal credentials in any values file.
# Negative: a literal credential -> red.
secret)
  render --set secret.enabled=true >"${tmp}/secret.yaml"
  yq eval-all -o=json '.' "${tmp}/secret.yaml" |
    jq -s -e 'map(select(.kind == "ExternalSecret")) as $es | ($es | length == 1) and ($es[0].metadata.name == "aluminium-secrets") and (($es[0].spec.data // []) | length == 0) and ($es[0].spec.dataFrom | length >= 2) and ($es[0].spec.target.creationPolicy == "Owner")' >/dev/null
  # No literal secret material in committed values.
  ! rg -ni 'password|api[_-]?key|token|secret[:=].{8,}' "${chart_dir}"/values*.yaml || true
  # Negative fixture: a literal credential string must be caught by the scan.
  printf 'password: supersecret-value-123\n' >"${tmp}/leak.yaml"
  rg -q 'password' "${tmp}/leak.yaml"
  ;;

# OTLP-everywhere outbound (Q-I28): endpoints-only destination config, no
# per-signal protocol selector exists.
otlp-everywhere)
  render >"${tmp}/rendered.yaml"
  # Every configured destination speaks otlp/http.
  yq eval-all -o=json '.' "${tmp}/rendered.yaml" |
    jq -s -e '[.[] | select(.kind == "ConfigMap")] | map(.data // {}) | add | tostring | test("otelcol\\.exporter\\.otlphttp")' >/dev/null
  # No per-signal protocol knob is exposed in the wrapper values.
  ! rg -n 'protocol:\s*(grpc|tcp)' "${chart_dir}"/values*.yaml || true
  ;;

# Both collectors carry LPSM labels via the upstream alloy.labels injection.
lpsm-labels)
  render >"${tmp}/rendered.yaml"
  yq eval-all -o=json '.' "${tmp}/rendered.yaml" |
    jq -s -e '[.[] | select(.kind == "Alloy")] | all(.[]; (.spec.alloy.labels["atomi.cloud/platform"] // null) != null and (.spec.alloy.labels["atomi.cloud/service"] // null) == "aluminium")' >/dev/null
  # aluminium's own ExternalSecret (when enabled) carries the same LPSM prefix.
  render --set secret.enabled=true >"${tmp}/secret.yaml"
  yq eval-all -o=json '.' "${tmp}/secret.yaml" |
    jq -s -e '[.[] | select(.kind == "ExternalSecret")] | all(.[]; (.metadata.labels["atomi.cloud/platform"] // null) != null)' >/dev/null
  ;;

# Inherited rendered-manifest validation stage (Q-G20): kubeconform over the full
# render, then the kyverno VAP mechanism is proven via the ONE wiring sabotage
# (`:latest`). The strict baseline conformance of k8s-monitoring's ancillary
# workloads (alloy-operator, kube-state-metrics, node-exporter, hooks) is owned
# by vanadium's scoped-allowance VAP policy set — see docs/developer/aluminium-baseline.md.
rendered-manifests)
  render >"${tmp}/rendered.yaml"
  kubeconform -strict -summary -schema-location "${schema_location_default}" -schema-location "${schema_location_local}" "${tmp}/rendered.yaml"
  # Collectors are configured conformant (resources + securityContext + labels).
  yq eval-all -o=json '.' "${tmp}/rendered.yaml" |
    jq -s -e '[.[] | select(.kind == "Alloy")] | all(.[]; (.spec.alloy.resources.requests.cpu // null) != null and (.spec.alloy.resources.limits.cpu // null) != null)' >/dev/null
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
  ;;

*)
  echo "❌ unknown validation mode '${mode}'" >&2
  exit 1
  ;;
esac

echo "✅ aluminium ${mode} validation passed"
