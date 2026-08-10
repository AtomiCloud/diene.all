#!/usr/bin/env bash
set -euo pipefail

mode="${1:-}"
release="${RELEASE:-helm-wrapper}"
namespace="${NAMESPACE:-sample}"
tmp="$(mktemp -d)"
trap 'rm -rf "${tmp}"' EXIT

[ -z "${mode}" ] && echo "❌ validation mode not set" >&2 && exit 1

bash ./scripts/local/vendor-chart-config.sh >/dev/null

case "${mode}" in
schema)
  helm lint chart --namespace "${namespace}" >/dev/null
  helm lint chart --namespace "${namespace}" --values chart/values.example.yaml >/dev/null
  helm lint chart --namespace "${namespace}" --values chart/values.example.yaml --values chart/values.lapras.yaml >/dev/null
  ;;
schema-drift)
  bash ./scripts/local/generate-chart-schema.sh "${tmp}/values.schema.json" >/dev/null
  cmp chart/values.schema.json "${tmp}/values.schema.json"
  ;;
lint)
  helm lint chart --namespace "${namespace}"
  helm lint chart --namespace "${namespace}" --values chart/values.example.yaml
  helm lint chart --namespace "${namespace}" --values chart/values.example.yaml --values chart/values.lapras.yaml
  ;;
render)
  helm template "${release}" chart --namespace "${namespace}" >/dev/null
  helm template "${release}" chart --namespace "${namespace}" --values chart/values.example.yaml >/dev/null
  helm template "${release}" chart --namespace "${namespace}" --values chart/values.example.yaml --values chart/values.lapras.yaml >/dev/null
  ;;
config-vendoring)
  helm template "${release}" chart --namespace "${namespace}" --values chart/values.example.yaml >"${tmp}/config.yaml"
  yq eval-all -o=json '.' "${tmp}/config.yaml" | jq -s -e 'map(select(.kind == "ConfigMap" and .metadata.name == "wrapper-config"))[0].data | has("application.yaml") and has("application.example.yaml")' >/dev/null
  ;;
labels)
  helm template "${release}" chart --namespace "${namespace}" --values chart/values.example.yaml --values chart/values.lapras.yaml >"${tmp}/rendered.yaml"
  yq eval-all -o=json '.' "${tmp}/rendered.yaml" | jq -s -e 'map(select(.kind != null)) | all(.[]; .metadata.labels["atomi.cloud/platform"] == "sample" and .metadata.labels["atomi.cloud/service"] == "wrapper" and .metadata.labels["atomi.cloud/module"] == "api" and .metadata.labels["atomi.cloud/layer"] == "2" and .metadata.labels["atomi.cloud/landscape"] == "example" and .metadata.labels["atomi.cloud/cluster"] == "lapras" and .metadata.annotations["atomi.cloud/platform"] == "sample")' >/dev/null
  helm template "${release}" chart --namespace "${namespace}" --values chart/values.example.yaml --values chart/values.lapras.yaml --set labelPrefix=example.dev >"${tmp}/override.yaml"
  yq eval-all -o=json '.' "${tmp}/override.yaml" | jq -s -e 'map(select(.kind != null)) | all(.[]; .metadata.labels["example.dev/platform"] == "sample" and .metadata.annotations["example.dev/service"] == "wrapper" and .metadata.labels["atomi.cloud/platform"] == null and .metadata.annotations["atomi.cloud/service"] == null)' >/dev/null
  ;;
reloader)
  helm template "${release}" chart --namespace "${namespace}" --values chart/values.example.yaml >"${tmp}/default.yaml"
  yq eval-all -o=json '.' "${tmp}/default.yaml" | jq -s -e 'map(select(.kind == "Deployment" or .kind == "StatefulSet" or .kind == "DaemonSet" or .kind == "Job")) | length > 0 and all(.[]; .metadata.annotations["reloader.stakater.com/auto"] == "true")' >/dev/null
  helm template "${release}" chart --namespace "${namespace}" --values chart/values.example.yaml --set workload.reloader.enabled=false >"${tmp}/optout.yaml"
  yq eval-all -o=json '.' "${tmp}/optout.yaml" | jq -s -e 'map(select(.kind == "Deployment"))[0].metadata.annotations["reloader.stakater.com/auto"] == null' >/dev/null
  ;;
secret)
  helm template "${release}" chart --namespace "${namespace}" --values chart/values.example.yaml --set secret.enabled=true >"${tmp}/secret.yaml"
  yq eval-all -o=json '.' "${tmp}/secret.yaml" | jq -s -e 'map(select(.kind == "ExternalSecret"))[0] as $secret | $secret.metadata.name == "wrapper-secrets" and $secret.spec.target.name == "wrapper" and ($secret.spec.data == null) and $secret.spec.dataFrom[0].rewrite[0].regexp.target == "SHARED_$1" and $secret.spec.dataFrom[1].rewrite[0].regexp.target == "WRAPPER_$1"' >/dev/null
  ;;
fullname)
  helm template "${release}" chart --namespace "${namespace}" --values chart/values.example.yaml >"${tmp}/names.yaml"
  yq eval-all -o=json '.' "${tmp}/names.yaml" | jq -s -e 'map(select(.kind != null) | .metadata.name) | all(.[]; test("^[a-z0-9]+-[a-z0-9]+$"))' >/dev/null
  yq -e '.upstream.fullnameOverride | test("^[a-z0-9]+-[a-z0-9]+$")' chart/values.yaml >/dev/null
  ;;
primordial)
  helm template "${release}" chart --namespace "${namespace}" --values chart/values.example.yaml --set primordial.enabled=true >"${tmp}/primordial.yaml"
  kubeconform -strict -summary -schema-location default -schema-location 'schemas/{{ .ResourceKind }}.json' "${tmp}/primordial.yaml"
  yq eval-all -o=json '.' "${tmp}/primordial.yaml" | jq -s -e 'map(select(.kind == "PlatformDependency"))[0].spec as $spec | [$spec.database, $spec.kv, $spec.cache, $spec.store] | map(. // {}) | add | to_entries | all(.[]; (.value.engine | keys) == [.value.type])' >/dev/null
  ! rg -n '(^|[[:space:]])(share|sharedVia|redirectUris|desiredVersion):' "${tmp}/primordial.yaml"
  ;;
lpsm)
  helm template "${release}" chart --namespace "${namespace}" --values chart/values.example.yaml >"${tmp}/lpsm.yaml"
  ordinary="$(yq -r 'select(.kind == "ConfigMap" and .metadata.name == "wrapper-contracts") | .data."lpsm.ordinaryHostname"' "${tmp}/lpsm.yaml")"
  instance="$(yq -r 'select(.kind == "ConfigMap" and .metadata.name == "wrapper-contracts") | .data."lpsm.instanceHostname"' "${tmp}/lpsm.yaml")"
  parsed="$(yq -r 'select(.kind == "ConfigMap" and .metadata.name == "wrapper-contracts") | .data."lpsm.parsed"' "${tmp}/lpsm.yaml")"
  [ "${ordinary}" != "api.wrapper.sample.example.cluster.atomi.cloud" ] && echo "❌ ordinary LPSM hostname mismatch" >&2 && exit 1
  [ "${instance}" != "api.wrapper.sample.run001.example.local.example.invalid" ] && echo "❌ instance LPSM hostname mismatch" >&2 && exit 1
  jq -e '.landscape == "example" and .platform == "sample" and .service == "wrapper" and .module == "api" and .instance == "run001"' <<<"${parsed}" >/dev/null
  label_a="$(helm template "${release}" chart --namespace "${namespace}" --values chart/values.example.yaml --set-string instance.physicalId=repository-a:pr-123 | yq -r 'select(.kind == "ConfigMap" and .metadata.name == "wrapper-contracts") | .data."instance.label"')"
  label_b="$(helm template "${release}" chart --namespace "${namespace}" --values chart/values.example.yaml --set-string instance.physicalId=repository-b:pr-123 | yq -r 'select(.kind == "ConfigMap" and .metadata.name == "wrapper-contracts") | .data."instance.label"')"
  [ "${label_a}" = "${label_b}" ] && echo "❌ repository-qualified instance labels collided" >&2 && exit 1
  long_id="$(printf 'repository-%080d' 1)"
  long_label="$(helm template "${release}" chart --namespace "${namespace}" --values chart/values.example.yaml --set-string instance.physicalId="${long_id}" | yq -r 'select(.kind == "ConfigMap" and .metadata.name == "wrapper-contracts") | .data."instance.label"')"
  [ "${#long_label}" -gt 63 ] && echo "❌ normalized instance label exceeds DNS-1123 length" >&2 && exit 1
  helm template "${release}" chart --namespace "${namespace}" --values chart/values.example.yaml --set-string contracts.lpsm.parseHostname=api-wrapper-sample-run001-example.local.example.invalid >/dev/null 2>&1 && echo "❌ dash-fused hostname was accepted" >&2 && exit 1
  ;;
lb)
  helm template "${release}" chart --namespace "${namespace}" --values chart/values.example.yaml --set gateway.provider=digitalocean >"${tmp}/do.yaml"
  helm template "${release}" chart --namespace "${namespace}" --values chart/values.example.yaml --set gateway.provider=oci --set-string gateway.oci.reservedPublicIp=203.0.113.10 >"${tmp}/oci.yaml"
  helm template "${release}" chart --namespace "${namespace}" --values chart/values.example.yaml --set gateway.provider=aws --set-string 'gateway.aws.subnetIds[0]=subnet-a' --set-string 'gateway.aws.subnetIds[1]=subnet-b' --set-string 'gateway.aws.eipAllocationIds[0]=eipalloc-a' --set-string 'gateway.aws.eipAllocationIds[1]=eipalloc-b' >"${tmp}/aws.yaml"
  yq eval-all -o=json '.' "${tmp}/do.yaml" | jq -s -e 'map(select(.kind == "Service" and .metadata.name == "wrapper-gateway"))[0] | .spec.type == "LoadBalancer" and .metadata.annotations["service.beta.kubernetes.io/aws-load-balancer-eip-allocations"] == null and .metadata.annotations["oci.oraclecloud.com/reserved-ips"] == null' >/dev/null
  yq eval-all -o=json '.' "${tmp}/oci.yaml" | jq -s -e 'map(select(.kind == "Service" and .metadata.name == "wrapper-gateway"))[0].metadata.annotations["oci.oraclecloud.com/reserved-ips"] == "203.0.113.10"' >/dev/null
  yq eval-all -o=json '.' "${tmp}/aws.yaml" | jq -s -e 'map(select(.kind == "Service" and .metadata.name == "wrapper-gateway"))[0] | .metadata.annotations["service.beta.kubernetes.io/aws-load-balancer-subnets"] == "subnet-a,subnet-b" and .metadata.annotations["service.beta.kubernetes.io/aws-load-balancer-eip-allocations"] == "eipalloc-a,eipalloc-b"' >/dev/null
  ! rg -n 'nodePort:|hostPort:' "${tmp}/do.yaml" "${tmp}/oci.yaml" "${tmp}/aws.yaml"
  ;;
task-surface)
  task --list-all | rg -q 'example:lapras:debug'
  task --list-all | rg -q 'example:lapras:template'
  task --list-all | rg -q 'example:lapras:install'
  task --list-all | rg -q 'example:lapras:remove'
  ;;
rendered-manifests)
  helm template "${release}" chart --namespace "${namespace}" --values chart/values.example.yaml >"${tmp}/rendered.yaml"
  kubeconform -strict -summary -schema-location default -schema-location 'schemas/{{ .ResourceKind }}.json' "${tmp}/rendered.yaml"
  yq eval-all 'select(.kind == "Deployment" or .kind == "StatefulSet" or .kind == "DaemonSet" or .kind == "Job" or .kind == "Service")' "${tmp}/rendered.yaml" >"${tmp}/vap-resources.yaml"
  kyverno apply policies/vap --resource "${tmp}/vap-resources.yaml" --detailed-results --remove-color
  ;;
publish-git)
  PUBLISH_MODE=git PUBLISH_DRY_RUN=true RELEASE_VERSION=v0.1.0 PUBLISH_OUTPUT_DIR="${tmp}/git" bash ./scripts/ci/publish.sh >/dev/null
  [ ! -s "${tmp}/git/diene-helm-wrapper-0.1.0.tgz" ] && echo "❌ git chart package missing" >&2 && exit 1
  [ ! -s "${tmp}/git/index.yaml" ] && echo "❌ git chart index missing" >&2 && exit 1
  ;;
publish-oci)
  PUBLISH_MODE=oci PUBLISH_DRY_RUN=true RELEASE_VERSION=v0.1.0 PUBLISH_OUTPUT_DIR="${tmp}/oci" bash ./scripts/ci/publish.sh >/dev/null
  [ ! -s "${tmp}/oci/diene-helm-wrapper-0.1.0.tgz" ] && echo "❌ OCI chart package missing" >&2 && exit 1
  rg -q '^oci://registry.example.invalid/charts$' "${tmp}/oci/oci-ref.txt"
  ;;
version)
  PUBLISH_MODE=git PUBLISH_DRY_RUN=true RELEASE_VERSION=v0.1.0 PUBLISH_OUTPUT_DIR="${tmp}/version" bash ./scripts/ci/publish.sh >/dev/null
  ;;
presence)
  test -s docs/developer/helm-wrapper-baseline.md
  test -s .claude/skills/helm-wrapper/SKILL.md
  test -s chart/templates/webhook-route.yaml
  test -s chart/templates/contracts.yaml
  test -s policies/vap/workload-baseline.yaml
  ;;
gateway-webhook-presence)
  rg -q '/healthz' docs/developer/helm-wrapper-baseline.md chart/values.yaml
  rg -q '/internal/webhooks/\{provider\}' docs/developer/helm-wrapper-baseline.md
  test -s chart/templates/webhook-route.yaml
  test -s chart/templates/contracts.yaml
  ;;
tokenization-presence)
  rg -q '^## Tokenization surface$' docs/developer/helm-wrapper-baseline.md
  rg -q 'repository-qualified physical instance id' docs/developer/helm-wrapper-baseline.md
  rg -q 'upstream chart name/version/repository' docs/developer/helm-wrapper-baseline.md
  ;;
*)
  echo "❌ unknown validation mode '${mode}'" >&2
  exit 1
  ;;
esac

echo "✅ Helm wrapper ${mode} validation passed"
