#!/usr/bin/env bash
set -euo pipefail

mode="${1:-}"
release="${RELEASE:-platinum}"
namespace="${NAMESPACE:-sulfoxide}"
tmp="$(mktemp -d)"
trap 'rm -rf "${tmp}"' EXIT

[ -z "${mode}" ] && echo "❌ validation mode not set" >&2 && exit 1

# Standard stacked-values render into a file. No config vendoring (platinum is config-free).
render() {
  helm template "${release}" chart --namespace "${namespace}" "$@" 2>/dev/null
}

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
  render --values chart/values.example.yaml >/dev/null
  render --values chart/values.example.yaml --values chart/values.lapras.yaml >/dev/null
  render --values chart/values.entei.yaml >/dev/null
  ;;
labels)
  render --values chart/values.example.yaml --values chart/values.lapras.yaml >"${tmp}/rendered.yaml"
  yq eval-all -o=json '.' "${tmp}/rendered.yaml" | jq -s -e 'map(select(.kind != null)) | all(.[]; .metadata.labels["atomi.cloud/platform"] == "sulfoxide" and .metadata.labels["atomi.cloud/service"] == "platinum" and .metadata.labels["atomi.cloud/module"] == "gateway" and .metadata.labels["atomi.cloud/layer"] == "1" and .metadata.labels["atomi.cloud/landscape"] == "example" and .metadata.labels["atomi.cloud/cluster"] == "lapras" and .metadata.annotations["atomi.cloud/platform"] == "sulfoxide")' >/dev/null
  render --values chart/values.example.yaml --values chart/values.lapras.yaml --set labelPrefix=example.dev >"${tmp}/override.yaml"
  yq eval-all -o=json '.' "${tmp}/override.yaml" | jq -s -e 'map(select(.kind != null)) | all(.[]; .metadata.labels["example.dev/platform"] == "sulfoxide" and .metadata.annotations["example.dev/service"] == "platinum" and .metadata.labels["atomi.cloud/platform"] == null and .metadata.annotations["atomi.cloud/service"] == null)' >/dev/null
  ;;
reloader)
  render --values chart/values.example.yaml >"${tmp}/default.yaml"
  yq eval-all -o=json '.' "${tmp}/default.yaml" | jq -s -e 'map(select(.kind == "Deployment" or .kind == "StatefulSet" or .kind == "DaemonSet" or .kind == "Job")) | length > 0 and all(.[]; .metadata.annotations["reloader.stakater.com/auto"] == "true")' >/dev/null
  render --values chart/values.example.yaml --set healthBackend.reloader.enabled=false >"${tmp}/optout.yaml"
  yq eval-all -o=json '.' "${tmp}/optout.yaml" | jq -s -e 'map(select(.kind == "Deployment"))[0].metadata.annotations["reloader.stakater.com/auto"] == null' >/dev/null
  ;;
fullname)
  render --values chart/values.example.yaml >"${tmp}/names.yaml"
  # Every namespaced platinum-owned resource is `<service>-<token>` (exactly one dash); the cluster-scoped GatewayClass is the bare classname.
  yq eval-all -o=json '.' "${tmp}/names.yaml" | jq -s -e 'map(select(.kind != null and .kind != "GatewayClass") | .metadata.name) | all(.[]; test("^[a-z0-9]+-[a-z0-9]+$"))' >/dev/null
  yq eval-all -o=json '.' "${tmp}/names.yaml" | jq -s -e 'map(select(.kind == "GatewayClass"))[0].metadata.name == "platinum"' >/dev/null
  yq -e '.upstream.fullnameOverride | test("^[a-z0-9]+-[a-z0-9]+$")' chart/values.yaml >/dev/null
  ;;
gateway-class)
  render --values chart/values.example.yaml >"${tmp}/gc.yaml"
  yq eval-all -o=json '.' "${tmp}/gc.yaml" | jq -s -e 'map(select(.kind == "GatewayClass"))[0] | .metadata.name == "platinum" and .spec.controllerName == "gateway.kgateway.dev/kgateway"' >/dev/null
  yq eval-all -o=json '.' "${tmp}/gc.yaml" | jq -s -e 'map(select(.kind == "Gateway"))[0] | .metadata.name == "platinum-gateway" and .spec.gatewayClassName == "platinum" and (.spec.listeners | length) == 1 and .spec.listeners[0].port == 80' >/dev/null
  ;;
gateway-health)
  render --values chart/values.example.yaml >"${tmp}/health.yaml"
  yq eval-all -o=json '.' "${tmp}/health.yaml" | jq -s -e 'map(select(.kind == "HTTPRoute"))[0] as $r | $r.metadata.name == "platinum-health" and $r.spec.parentRefs[0].name == "platinum-gateway" and $r.spec.rules[0].matches[0].path.value == "/healthz" and $r.spec.rules[0].backendRefs[0].name == "platinum-api"' >/dev/null
  ;;
registered-cert)
  render --values chart/values.example.yaml >"${tmp}/certs.yaml"
  yq eval-all -o=json '.' "${tmp}/certs.yaml" | jq -s -e 'map(select(.kind == "Certificate")) | length == 2 and all(.[]; .spec.issuerRef.kind == "ClusterIssuer" and .spec.issuerRef.name == "zinc-wildcard-letsencrypt" and (.spec.commonName | startswith("*.")))' >/dev/null
  ;;
entei-overlay)
  render --values chart/values.entei.yaml >"${tmp}/entei.yaml"
  # dev-host renders the shared GatewayClass, Gateway, and LoadBalancer only.
  yq eval-all -o=json '.' "${tmp}/entei.yaml" | jq -s -e 'map(select(.kind == "GatewayClass")) | length == 1 and all(.[]; .metadata.name == "platinum")' >/dev/null
  yq eval-all -o=json '.' "${tmp}/entei.yaml" | jq -s -e 'map(select(.kind == "Gateway")) | length == 1' >/dev/null
  yq eval-all -o=json '.' "${tmp}/entei.yaml" | jq -s -e 'map(select(.kind == "Service" and .spec.type == "LoadBalancer")) | length == 1' >/dev/null
  # No per-host Certificate, ListenerSet, or HTTPRoute is owned by this chart in dev-host mode.
  ! rg -n 'kind: (ListenerSet|HTTPRoute)' "${tmp}/entei.yaml"
  yq eval-all -o=json '.' "${tmp}/entei.yaml" | jq -s -e 'map(select(.kind == "Certificate")) | length == 0' >/dev/null
  ;;
lb)
  render --values chart/values.example.yaml --set gateway.provider=digitalocean >"${tmp}/do.yaml"
  render --values chart/values.example.yaml --set gateway.provider=oci --set-string gateway.oci.reservedPublicIp=203.0.113.10 >"${tmp}/oci.yaml"
  render --values chart/values.example.yaml --set gateway.provider=aws --set-string 'gateway.aws.subnetIds[0]=subnet-a' --set-string 'gateway.aws.subnetIds[1]=subnet-b' --set-string 'gateway.aws.eipAllocationIds[0]=eipalloc-a' --set-string 'gateway.aws.eipAllocationIds[1]=eipalloc-b' >"${tmp}/aws.yaml"
  yq eval-all -o=json '.' "${tmp}/do.yaml" | jq -s -e 'map(select(.kind == "Service" and .metadata.name == "platinum-edge"))[0] | .spec.type == "LoadBalancer" and .metadata.annotations["service.beta.kubernetes.io/aws-load-balancer-eip-allocations"] == null and .metadata.annotations["oci.oraclecloud.com/reserved-ips"] == null' >/dev/null
  yq eval-all -o=json '.' "${tmp}/oci.yaml" | jq -s -e 'map(select(.kind == "Service" and .metadata.name == "platinum-edge"))[0].metadata.annotations["oci.oraclecloud.com/reserved-ips"] == "203.0.113.10"' >/dev/null
  yq eval-all -o=json '.' "${tmp}/aws.yaml" | jq -s -e 'map(select(.kind == "Service" and .metadata.name == "platinum-edge"))[0] | .metadata.annotations["service.beta.kubernetes.io/aws-load-balancer-subnets"] == "subnet-a,subnet-b" and .metadata.annotations["service.beta.kubernetes.io/aws-load-balancer-eip-allocations"] == "eipalloc-a,eipalloc-b"' >/dev/null
  ! rg -n 'nodePort:|hostPort:' "${tmp}/do.yaml" "${tmp}/oci.yaml" "${tmp}/aws.yaml"
  ;;
task-surface)
  task --list-all | rg -q 'example:lapras:debug'
  task --list-all | rg -q 'example:lapras:template'
  task --list-all | rg -q 'example:lapras:install'
  task --list-all | rg -q 'example:lapras:remove'
  ;;
rendered-manifests)
  render --values chart/values.example.yaml --values chart/values.lapras.yaml >"${tmp}/rendered.yaml"
  kubeconform -strict -summary -schema-location default -schema-location 'schemas/{{ .ResourceKind }}.json' "${tmp}/rendered.yaml"
  yq eval-all 'select(.kind == "Deployment" or .kind == "StatefulSet" or .kind == "DaemonSet" or .kind == "Job" or .kind == "Service")' "${tmp}/rendered.yaml" >"${tmp}/vap-resources.yaml"
  kyverno apply policies/vap --resource "${tmp}/vap-resources.yaml" --detailed-results --remove-color
  ;;
vap-sabotage)
  # ONE Q-G20 wiring sabotage: a reappearing NodePort surface must trip the service-baseline VAP.
  render --values chart/values.example.yaml --values chart/values.lapras.yaml >"${tmp}/rendered.yaml"
  yq eval-all 'select(.kind == "Service" and .metadata.name == "platinum-edge")' "${tmp}/rendered.yaml" |
    sed 's/type: LoadBalancer/type: NodePort/' >"${tmp}/sabotaged-service.yaml"
  kyverno apply policies/vap/service-baseline.yaml --resource "${tmp}/sabotaged-service.yaml" --detailed-results --remove-color >"${tmp}/vap-out.txt" 2>&1 ||
    { grep -q 'fail: 1' "${tmp}/vap-out.txt" && echo "sabotage correctly caught (NodePort rejected)"; }
  grep -q 'fail: 1' "${tmp}/vap-out.txt" || {
    echo "❌ NodePort sabotage was NOT caught" >&2
    cat "${tmp}/vap-out.txt"
    exit 1
  }
  ;;
publish-git)
  PUBLISH_MODE=git PUBLISH_DRY_RUN=true RELEASE_VERSION=v0.1.0 PUBLISH_OUTPUT_DIR="${tmp}/git" bash ./scripts/ci/publish.sh >/dev/null
  [ ! -s "${tmp}/git/platinum-0.1.0.tgz" ] && echo "❌ git chart package missing" >&2 && exit 1
  [ ! -s "${tmp}/git/index.yaml" ] && echo "❌ git chart index missing" >&2 && exit 1
  ;;
publish-oci)
  PUBLISH_MODE=oci PUBLISH_DRY_RUN=true RELEASE_VERSION=v0.1.0 PUBLISH_OUTPUT_DIR="${tmp}/oci" bash ./scripts/ci/publish.sh >/dev/null
  [ ! -s "${tmp}/oci/platinum-0.1.0.tgz" ] && echo "❌ OCI chart package missing" >&2 && exit 1
  rg -q '^oci://registry.example.invalid/charts$' "${tmp}/oci/oci-ref.txt"
  ;;
version)
  PUBLISH_MODE=git PUBLISH_DRY_RUN=true RELEASE_VERSION=v0.1.0 PUBLISH_OUTPUT_DIR="${tmp}/version" bash ./scripts/ci/publish.sh >/dev/null
  ;;
presence)
  test -s docs/developer/platinum-baseline.md
  test -s .claude/skills/platinum/SKILL.md
  test -s chart/templates/gatewayclass.yaml
  test -s chart/templates/gateway.yaml
  test -s chart/templates/gateway-service.yaml
  test -s chart/templates/gateway-health-route.yaml
  test -s chart/templates/health-backend.yaml
  test -s chart/templates/registered-certificates.yaml
  test -s policies/vap/workload-baseline.yaml
  test -s policies/vap/service-baseline.yaml
  ;;
tokenization-presence)
  rg -q '^## Tokenization surface$' docs/developer/platinum-baseline.md
  rg -q 'repository-qualified physical instance id' docs/developer/platinum-baseline.md
  rg -q 'upstream chart name/version/repository' docs/developer/platinum-baseline.md
  ;;
*)
  echo "❌ unknown validation mode '${mode}'" >&2
  exit 1
  ;;
esac

echo "✅ Platinum ${mode} validation passed"
