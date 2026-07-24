#!/usr/bin/env bash
# Xenon unit-tier validation (materialized chart product — no probe matrix).
# One mode per independently invoked mechanism; the CI orchestrator calls them in order.
set -euo pipefail

mode="${1:-}"
release="${RELEASE:-xenon}"
namespace="${NAMESPACE:-sample}"
matrix_json="$(yq -o=json '.' chart/toggle-map.yaml)"
tmp="$(mktemp -d)"
trap 'rm -rf "${tmp}"' EXIT

[ -z "${mode}" ] && echo "❌ validation mode not set" >&2 && exit 1

case "${mode}" in
schema)
  helm lint chart --namespace "${namespace}" >/dev/null
  while IFS= read -r landscape_entry; do
    helm_args=()
    while IFS= read -r overlay; do
      helm_args+=(--values "${overlay}")
    done < <(printf '%s' "${landscape_entry}" | jq -r '.overlays[]')
    helm lint chart --namespace "${namespace}" "${helm_args[@]}" >/dev/null
  done < <(printf '%s' "${matrix_json}" | jq -c '.landscapes[]')
  ;;
schema-negative)
  yq '.metricsServer.replicas = 0' chart/values.yaml >"${tmp}/invalid-values.yaml"
  if helm lint chart --namespace "${namespace}" --values chart/values.pichu.yaml --values "${tmp}/invalid-values.yaml" >"${tmp}/schema.stdout" 2>"${tmp}/schema.stderr"; then
    echo "❌ replicas=0 passed Helm schema validation" >&2
    exit 1
  fi
  rg -qi 'replicas.*(greater than or equal to 1|minimum)' "${tmp}/schema.stdout" "${tmp}/schema.stderr"
  ;;
schema-drift)
  bash ./scripts/local/generate-chart-schema.sh "${tmp}/values.schema.json" >/dev/null
  cmp chart/values.schema.json "${tmp}/values.schema.json"
  ;;
dependency)
  bash ./scripts/local/vendor-metrics-server.sh build >/dev/null
  chart_version="$(yq -r '.dependencies[] | select(.name == "metrics-server") | .version' chart/Chart.yaml)"
  lock_version="$(yq -r '.dependencies[] | select(.name == "metrics-server") | .version' chart/Chart.lock)"
  app_version="$(yq -r '.appVersion' chart/Chart.yaml)"
  evidence_version="$(yq -r '.chart.version' chart/upstream-evidence.yaml)"
  evidence_app="$(yq -r '.chart.appVersion' chart/upstream-evidence.yaml)"
  archive="chart/charts/metrics-server-${chart_version}.tgz"
  [ "${chart_version}" != "${lock_version}" ] && echo "❌ Chart.yaml and Chart.lock dependency versions differ" >&2 && exit 1
  [ "${chart_version}" != "${evidence_version}" ] && echo "❌ selected chart and upstream evidence versions differ" >&2 && exit 1
  [ "${app_version}" != "${evidence_app}" ] && echo "❌ selected app and upstream evidence versions differ" >&2 && exit 1
  [ "$(find chart/charts -maxdepth 1 -type f -name 'metrics-server-*.tgz' | wc -l)" -ne 1 ] && echo "❌ vendored metrics-server archive inventory is not singular" >&2 && exit 1
  [ ! -s "${archive}" ] && echo "❌ vendored metrics-server archive is missing" >&2 && exit 1
  [ "$(sha256sum "${archive}" | awk '{print $1}')" != "$(yq -r '.chart.patchedArchiveSha256' chart/upstream-evidence.yaml)" ] && echo "❌ vendored metrics-server archive hash drifted" >&2 && exit 1
  ;;
upstream)
  bash ./scripts/local/latest-chart-upstreams.sh
  ;;
lint)
  helm lint chart --namespace "${namespace}"
  while IFS= read -r landscape_entry; do
    landscape="$(printf '%s' "${landscape_entry}" | jq -r '.landscape')"
    helm_args=()
    while IFS= read -r overlay; do
      helm_args+=(--values "${overlay}")
    done < <(printf '%s' "${landscape_entry}" | jq -r '.overlays[]')
    echo "🔎 linting ${landscape} stack"
    helm lint chart --namespace "${namespace}" "${helm_args[@]}"
  done < <(printf '%s' "${matrix_json}" | jq -c '.landscapes[]')
  ;;
render)
  helm template "${release}" chart --namespace "${namespace}" >/dev/null
  while IFS= read -r landscape_entry; do
    helm_args=()
    while IFS= read -r overlay; do
      helm_args+=(--values "${overlay}")
    done < <(printf '%s' "${landscape_entry}" | jq -r '.overlays[]')
    helm template "${release}" chart --namespace "${namespace}" "${helm_args[@]}" >/dev/null
  done < <(printf '%s' "${matrix_json}" | jq -c '.landscapes[]')
  ;;
labels)
  yq -e '.global.serviceTree | has("platform") | not' chart/values.yaml >/dev/null
  helm template "${release}" chart --namespace "${namespace}" --values chart/values.pichu.yaml >"${tmp}/rendered.yaml"
  yq eval-all -o=json '.' "${tmp}/rendered.yaml" | jq --arg ns "${namespace}" -se '
    def lpsm($prefix; $namespace):
      (.[$prefix + "/platform"] == $namespace)
      and (.[$prefix + "/service"] == "xenon")
      and (.[$prefix + "/module"] == "metrics")
      and (.[$prefix + "/layer"] == "1")
      and (.[$prefix + "/landscape"] == "pichu");
    . as $resources
    | ($resources | map(select(.kind == "Deployment" and .metadata.name == "xenon-metrics"))) as $deployments
    | ($resources | map(select(.kind == "ConfigMap" and .metadata.name == "xenon-lpsm"))) as $configmaps
    | ($deployments | length) == 1
      and ($configmaps | length) == 1
      and ($configmaps[0].metadata.labels | lpsm("atomi.cloud"; $ns))
      and ($configmaps[0].metadata.annotations | lpsm("atomi.cloud"; $ns))
      and ($deployments[0].metadata.labels | lpsm("atomi.cloud"; $ns))
      and ($deployments[0].metadata.annotations | lpsm("atomi.cloud"; $ns))
      and ($deployments[0].spec.template.metadata.labels | lpsm("atomi.cloud"; $ns))
      and ($deployments[0].spec.template.metadata.annotations | lpsm("atomi.cloud"; $ns))
  ' >/dev/null
  helm template "${release}" chart --namespace tenant --values chart/values.pichu.yaml --set global.labelPrefix=example.dev >"${tmp}/override.yaml"
  yq eval-all -o=json '.' "${tmp}/override.yaml" | jq -se '
    def lpsm:
      (. ["example.dev/platform"] == "tenant")
      and (. ["example.dev/service"] == "xenon")
      and (. ["example.dev/module"] == "metrics")
      and (. ["example.dev/layer"] == "1")
      and (. ["example.dev/landscape"] == "pichu");
    . as $resources
    | ($resources | map(select(.kind == "Deployment" and .metadata.name == "xenon-metrics"))[0]) as $deployment
    | ($resources | map(select(.kind == "ConfigMap" and .metadata.name == "xenon-lpsm"))[0]) as $configmap
    | ($configmap.metadata.labels | lpsm)
      and ($configmap.metadata.annotations | lpsm)
      and ($deployment.metadata.labels | lpsm)
      and ($deployment.metadata.annotations | lpsm)
      and ($deployment.spec.template.metadata.labels | lpsm)
      and ($deployment.spec.template.metadata.annotations | lpsm)
      and ([
        $configmap.metadata.labels,
        $configmap.metadata.annotations,
        $deployment.metadata.labels,
        $deployment.metadata.annotations,
        $deployment.spec.template.metadata.labels,
        $deployment.spec.template.metadata.annotations
      ] | map(to_entries[]) | map(select(.key | startswith("atomi.cloud/"))) | length) == 0
  ' >/dev/null
  if helm template "${release}" chart --namespace tenant --values chart/values.pichu.yaml --set global.serviceTree.platform=wrong >/dev/null 2>&1; then
    echo "❌ a duplicate free platform value was accepted" >&2
    exit 1
  fi
  ;;
reloader)
  helm template "${release}" chart --namespace "${namespace}" --values chart/values.pichu.yaml >"${tmp}/default.yaml"
  yq eval-all -o=json '.' "${tmp}/default.yaml" | jq -s -e 'map(select(.kind == "Deployment" and .metadata.name == "xenon-metrics"))[0].spec.template.metadata.annotations["reloader.stakater.com/auto"] == "true"' >/dev/null
  yq -n '.metricsServer.podAnnotations."reloader.stakater.com/auto" = "false"' >"${tmp}/optout.yaml"
  helm template "${release}" chart --namespace "${namespace}" --values chart/values.pichu.yaml --values "${tmp}/optout.yaml" >"${tmp}/optout-render.yaml"
  yq eval-all -o=json '.' "${tmp}/optout-render.yaml" | jq -s -e 'map(select(.kind == "Deployment" and .metadata.name == "xenon-metrics"))[0].spec.template.metadata.annotations["reloader.stakater.com/auto"] == "false"' >/dev/null
  ;;
fullname)
  yq -e '.metricsServer.fullnameOverride | test("^[a-z0-9]+-[a-z0-9]+$")' chart/values.yaml >/dev/null
  helm template "${release}" chart --namespace "${namespace}" --values chart/values.pichu.yaml \
    --set metricsServer.addonResizer.enabled=true \
    --set metricsServer.podDisruptionBudget.enabled=true \
    --set metricsServer.metrics.enabled=true \
    --set metricsServer.serviceMonitor.enabled=true \
    --set metricsServer.tls.type=cert-manager \
    --api-versions cert-manager.io/v1 \
    --api-versions monitoring.coreos.com/v1 >"${tmp}/names.yaml"
  yq eval-all -o=json '.' "${tmp}/names.yaml" | jq -se '
    map(select(type == "object" and has("kind"))) as $resources
    | ([ $resources[] | select(.kind == "APIService" and .metadata.name == "v1beta1.metrics.k8s.io") ] | length) == 1
      and all($resources[];
        if .kind == "APIService" then .metadata.name == "v1beta1.metrics.k8s.io"
        else (.metadata.name | test("^xenon-[a-z0-9]+$")) end)
      and all($resources[] | select(.kind == "ClusterRoleBinding" and (.roleRef.name | startswith("xenon-")));
        .roleRef.name as $role | any($resources[]; .kind == "ClusterRole" and .metadata.name == $role))
  ' >/dev/null
  ;;
task-surface)
  # Capture the task list once, then match against the buffer. Piping
  # `task --list-all | rg -q` races a SIGPIPE (exit 141) under `pipefail`:
  # `rg -q` closes the pipe on the first match while `task` is still writing.
  task_surface="$(task --list-all)"
  rg -q 'lapras:k3d:debug' <<<"${task_surface}"
  rg -q 'lapras:k3d:template' <<<"${task_surface}"
  rg -q 'lapras:k3d:install' <<<"${task_surface}"
  rg -q 'lapras:k3d:remove' <<<"${task_surface}"
  ;;
sit-handoff)
  bash -n ./scripts/validate/xenon-sit.sh
  bash -n ./scripts/validate/xenon-sit-cleanup.sh
  rg -q 'helm install' scripts/validate/xenon-sit.sh
  if rg -q 'helm upgrade' scripts/validate/xenon-sit.sh; then
    echo "❌ SIT handoff retains upgrading Helm semantics" >&2
    exit 1
  fi
  rg -q -- '--atomic --wait' scripts/validate/xenon-sit.sh
  rg -q -- '--labels' scripts/validate/xenon-sit.sh
  rg -q -- '--selector' scripts/validate/xenon-sit-cleanup.sh
  rg -q 'ownership\.claim' scripts/validate/xenon-sit.sh scripts/validate/xenon-sit-cleanup.sh
  rg -q 'helm uninstall' scripts/validate/xenon-sit-cleanup.sh
  rg -q 'failed-uninstall' scripts/validate/xenon-sit-cleanup.sh
  rg -q 'failed-owner-mismatch' scripts/validate/xenon-sit-cleanup.sh
  for artifact in sit.stdout sit.stderr preflight-values preflight-render helm-install rollout helm-status top-nodes top-pods cleanup-owner cleanup-uninstall cleanup.status; do
    rg -q "${artifact}" scripts/validate/xenon-sit.sh scripts/validate/xenon-sit-cleanup.sh
  done

  real_helm="$(command -v helm)"
  export REAL_HELM="${real_helm}"
  export FAKE_HELM_LOG="${tmp}/disabled-helm.log"
  export FAKE_KUBECTL_LOG="${tmp}/disabled-kubectl.log"
  # shellcheck disable=SC2329 # Exported into the child SIT harness.
  helm() {
    printf '%s\n' "$*" >>"${FAKE_HELM_LOG}"
    return 97
  }
  # shellcheck disable=SC2329 # Exported into the child SIT harness.
  kubectl() {
    printf '%s\n' "$*" >>"${FAKE_KUBECTL_LOG}"
    return 98
  }
  export -f helm kubectl
  if SIT_CONTEXT=fake-context \
    SIT_NAMESPACE=sample \
    RELEASE=xenon \
    SIT_VALUES_FILE="$(realpath chart/values.lapras.yaml)" \
    SIT_EVIDENCE_DIR="${tmp}/disabled-evidence" \
    bash ./scripts/validate/xenon-sit.sh >"${tmp}/disabled.stdout" 2>"${tmp}/disabled.stderr"; then
    echo "❌ disabled SIT values reached a successful handoff" >&2
    exit 1
  fi
  if [ -s "${FAKE_HELM_LOG}" ] || [ -s "${FAKE_KUBECTL_LOG}" ]; then
    echo "❌ disabled SIT values reached a cluster-facing command" >&2
    exit 1
  fi
  rg -q 'authoritative toggle-map ON stack' "${tmp}/disabled-evidence/sit.stderr"

  export FAKE_HELM_LOG="${tmp}/race-helm.log"
  export FAKE_HELM_INSTALL_ATTEMPT="${tmp}/race-install-attempt"
  export FAKE_HELM_UNINSTALL_ATTEMPT="${tmp}/race-uninstall-attempt"
  export FAKE_KUBECTL_LOG="${tmp}/race-kubectl.log"
  helm() {
    printf '%s\n' "$*" >>"${FAKE_HELM_LOG}"
    case "${1:-}" in
    template)
      "${REAL_HELM}" "$@"
      ;;
    list)
      local has_selector=false
      local arg
      for arg in "$@"; do
        [ "${arg}" = "--selector" ] && has_selector=true
      done
      if [ "${has_selector}" = "true" ]; then
        printf '%s\n' '[]'
      elif [ -e "${FAKE_HELM_INSTALL_ATTEMPT}" ]; then
        printf '%s\n' '[{"name":"xenon"}]'
      else
        printf '%s\n' '[]'
      fi
      ;;
    install)
      : >"${FAKE_HELM_INSTALL_ATTEMPT}"
      echo "simulated same-name install collision" >&2
      return 1
      ;;
    uninstall)
      : >"${FAKE_HELM_UNINSTALL_ATTEMPT}"
      return 99
      ;;
    *)
      echo "unexpected fake Helm command: ${1:-<empty>}" >&2
      return 96
      ;;
    esac
  }
  kubectl() {
    printf '%s\n' "$*" >>"${FAKE_KUBECTL_LOG}"
    return 95
  }
  export -f helm kubectl
  if SIT_CONTEXT=fake-context \
    SIT_NAMESPACE=sample \
    RELEASE=xenon \
    SIT_VALUES_FILE="$(realpath chart/values.pichu.yaml)" \
    SIT_EVIDENCE_DIR="${tmp}/race-evidence" \
    bash ./scripts/validate/xenon-sit.sh >"${tmp}/race.stdout" 2>"${tmp}/race.stderr"; then
    echo "❌ same-name ownership race did not fail the SIT handoff" >&2
    exit 1
  fi
  rg -q '^install ' "${FAKE_HELM_LOG}"
  if rg -q '^(upgrade|uninstall) ' "${FAKE_HELM_LOG}" || [ -e "${FAKE_HELM_UNINSTALL_ATTEMPT}" ]; then
    echo "❌ same-name ownership race reached upgrade or uninstall" >&2
    exit 1
  fi
  if [ -s "${FAKE_KUBECTL_LOG}" ]; then
    echo "❌ failed collision unexpectedly reached kubectl" >&2
    exit 1
  fi
  rg -qx 'failed-owner-mismatch' "${tmp}/race-evidence/cleanup.status"
  run_id="$(jq -r '.runId' "${tmp}/race-evidence/inputs.json")"
  ownership_label_key="$(jq -r '.ownershipLabel.key' "${tmp}/race-evidence/inputs.json")"
  jq -e --slurpfile claim "${tmp}/race-evidence/ownership.claim" '
    .runId == $claim[0].runId
    and .ownershipLabel == $claim[0].ownershipLabel
    and .landscape == "pichu"
  ' "${tmp}/race-evidence/inputs.json" >/dev/null
  jq -e '.metricsServer.enabled == true' "${tmp}/race-evidence/preflight-values.json" >/dev/null
  yq eval-all -o=json '.' "${tmp}/race-evidence/preflight-render.yaml" | jq -se --arg key "${ownership_label_key}" --arg runId "${run_id}" '
    map(select(type == "object" and .kind == "Deployment" and .metadata.name == "xenon-metrics"))
    | length == 1
      and .[0].metadata.labels[$key] == $runId
      and .[0].spec.template.metadata.labels[$key] == $runId
  ' >/dev/null
  rg -F -q -- "--labels ${ownership_label_key}=${run_id}" "${FAKE_HELM_LOG}"
  rg -F -q -- "--selector ${ownership_label_key}=${run_id}" "${FAKE_HELM_LOG}"
  ;;
toggle-map)
  bash ./scripts/validate/check-xenon-toggle-map.sh
  yq '.metricsServer.enabled = true' chart/values.lapras.yaml >"${tmp}/lapras-on.yaml"
  if TOGGLE_REPLACE_PATH=chart/values.lapras.yaml TOGGLE_REPLACE_WITH="${tmp}/lapras-on.yaml" bash ./scripts/validate/check-xenon-toggle-map.sh >/dev/null 2>&1; then
    echo "❌ lapras OFF→ON mutation did not redden the authoritative matrix checker" >&2
    exit 1
  fi
  ;;
rendered-manifests)
  while IFS= read -r landscape_entry; do
    enabled="$(printf '%s' "${landscape_entry}" | jq -r '.enabled')"
    [ "${enabled}" != "true" ] && continue
    landscape="$(printf '%s' "${landscape_entry}" | jq -r '.landscape')"
    helm_args=()
    while IFS= read -r overlay; do
      helm_args+=(--values "${overlay}")
    done < <(printf '%s' "${landscape_entry}" | jq -r '.overlays[]')
    helm template "${release}" chart --namespace "${namespace}" "${helm_args[@]}" >"${tmp}/${landscape}.yaml"
    kubeconform -strict -summary "${tmp}/${landscape}.yaml"
    yq eval-all 'select(.kind == "Deployment" or .kind == "StatefulSet" or .kind == "DaemonSet" or .kind == "Job" or .kind == "Service")' "${tmp}/${landscape}.yaml" >"${tmp}/${landscape}-vap.yaml"
    kyverno apply policies/vap --resource "${tmp}/${landscape}-vap.yaml" --detailed-results --remove-color
  done < <(printf '%s' "${matrix_json}" | jq -c '.landscapes[]')
  ;;
vap-sabotage)
  helm template "${release}" chart --namespace "${namespace}" --values chart/values.pichu.yaml --set metricsServer.image.tag=latest >"${tmp}/rendered.yaml" 2>/dev/null
  yq eval-all 'select(.kind == "Deployment" or .kind == "Service")' "${tmp}/rendered.yaml" >"${tmp}/vap-resources.yaml"
  if kyverno apply policies/vap --resource "${tmp}/vap-resources.yaml" --remove-color >/dev/null 2>&1; then
    echo "❌ :latest wiring sabotage was not caught by the VAP stage" >&2
    exit 1
  fi
  ;;
publish-git)
  PUBLISH_MODE=git PUBLISH_DRY_RUN=true RELEASE_VERSION=v0.1.0 PUBLISH_OUTPUT_DIR="${tmp}/git" bash ./scripts/ci/publish.sh >/dev/null
  [ ! -s "${tmp}/git/diene-xenon-0.1.0.tgz" ] && echo "❌ git chart package missing" >&2 && exit 1
  [ ! -s "${tmp}/git/index.yaml" ] && echo "❌ git chart index missing" >&2 && exit 1
  ;;
publish-oci)
  PUBLISH_MODE=oci PUBLISH_DRY_RUN=true RELEASE_VERSION=v0.1.0 PUBLISH_OUTPUT_DIR="${tmp}/oci" bash ./scripts/ci/publish.sh >/dev/null
  [ ! -s "${tmp}/oci/diene-xenon-0.1.0.tgz" ] && echo "❌ OCI chart package missing" >&2 && exit 1
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
  test -s docs/developer/xenon-baseline.md
  test -s chart/toggle-map.yaml
  test -s chart/upstream-evidence.yaml
  test -s chart/patches/metrics-server-3.13.1-xenon.patch
  test -s chart/templates/lpsm-configmap.yaml
  test -s policies/vap/workload-baseline.yaml
  test -s policies/vap/service-baseline.yaml
  test -x scripts/local/vendor-metrics-server.sh
  test -x scripts/validate/check-xenon-toggle-map.sh
  test -x scripts/validate/xenon-sit-cleanup.sh
  ;;
*)
  echo "❌ unknown validation mode '${mode}'" >&2
  exit 1
  ;;
esac

echo "✅ Xenon ${mode} validation passed"
