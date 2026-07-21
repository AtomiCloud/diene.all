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
  helm lint chart --namespace "${namespace}" --values chart/values.example.yaml --values chart/values.aws.yaml >/dev/null
  helm lint chart --namespace "${namespace}" --values chart/values.example.yaml --values chart/values.oci.yaml >/dev/null
  helm lint chart --namespace "${namespace}" --values chart/values.example.yaml --values chart/values.digitalocean.yaml >/dev/null
  helm lint chart --namespace "${namespace}" --values chart/values.entei.yaml >/dev/null
  ;;
schema-drift)
  bash ./scripts/local/generate-chart-schema.sh "${tmp}/values.schema.json" >/dev/null
  cmp chart/values.schema.json "${tmp}/values.schema.json"
  ;;
lint)
  helm lint chart --namespace "${namespace}"
  helm lint chart --namespace "${namespace}" --values chart/values.example.yaml
  helm lint chart --namespace "${namespace}" --values chart/values.example.yaml --values chart/values.lapras.yaml
  helm lint chart --namespace "${namespace}" --values chart/values.example.yaml --values chart/values.aws.yaml
  helm lint chart --namespace "${namespace}" --values chart/values.example.yaml --values chart/values.oci.yaml
  helm lint chart --namespace "${namespace}" --values chart/values.example.yaml --values chart/values.digitalocean.yaml
  helm lint chart --namespace "${namespace}" --values chart/values.entei.yaml
  ;;
render)
  render --values chart/values.example.yaml >/dev/null
  render --values chart/values.example.yaml --values chart/values.lapras.yaml >/dev/null
  render --values chart/values.example.yaml --values chart/values.aws.yaml >/dev/null
  render --values chart/values.example.yaml --values chart/values.oci.yaml >/dev/null
  render --values chart/values.example.yaml --values chart/values.digitalocean.yaml >/dev/null
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
  yq eval-all -o=json '.' "${tmp}/gc.yaml" | jq -s -e 'map(select(.kind == "GatewayClass"))[0] | .metadata.name == "platinum" and .spec.controllerName == "kgateway.dev/kgateway"' >/dev/null
  yq eval-all -o=json '.' "${tmp}/gc.yaml" | jq -s -e 'map(select(.kind == "Gateway"))[0] | .metadata.name == "platinum-gateway" and .spec.gatewayClassName == "platinum" and ([.spec.listeners[].protocol] | sort) == ["HTTP", "HTTPS", "HTTPS"]' >/dev/null
  if render --values chart/values.example.yaml --set-string gateway.controllerName=example.invalid/controller >"${tmp}/wrong-controller.yaml"; then
    echo "❌ non-kgateway controller binding passed schema/render validation" >&2
    exit 1
  fi
  ;;
gateway-proxy)
  render --values chart/values.example.yaml --values chart/values.lapras.yaml --set upstream.enabled=true >"${tmp}/enabled.yaml"
  yq -e '.dependencies[] | select(.name == "kgateway") | .version == "v2.2.9"' chart/Chart.lock >/dev/null
  yq eval-all -o=json '.' "${tmp}/enabled.yaml" | jq -s -e 'map(select(.kind == "Deployment" and .metadata.name == "platinum-upstream")) | length == 1' >/dev/null
  yq eval-all -o=json '.' "${tmp}/enabled.yaml" | jq -s -e 'map(select(.kind == "Service" and .metadata.name == "platinum-edge"))[0]' >"${tmp}/edge.json"
  yq eval-all -o=json '.' tests/fixtures/kgateway-v2.2.9-proxy-render.yaml | jq -s -e 'map(select(.kind == "Service"))[0]' >"${tmp}/proxy-service.json"
  yq eval-all -o=json '.' tests/fixtures/kgateway-v2.2.9-proxy-render.yaml | jq -s -e 'map(select(.kind == "Deployment"))[0]' >"${tmp}/proxy-deployment.json"
  jq -e --slurpfile proxyService "${tmp}/proxy-service.json" --slurpfile proxyDeployment "${tmp}/proxy-deployment.json" '
    .spec.selector == $proxyService[0].spec.selector and
    ([.spec.ports[] | {name, targetPort}] | sort_by(.targetPort)) == ([$proxyService[0].spec.ports[] | {name, targetPort}] | sort_by(.targetPort)) and
    ([$proxyService[0].spec.ports[] | {name, targetPort}] | sort_by(.targetPort)) == ([$proxyDeployment[0].spec.template.spec.containers[0].ports[] | {name, targetPort: .containerPort}] | sort_by(.targetPort))
  ' "${tmp}/edge.json" >/dev/null
  if render --values chart/values.example.yaml --set gateway.proxy.selector=null >"${tmp}/missing-selector.yaml"; then
    echo "❌ missing generated-proxy selector rendered successfully" >&2
    exit 1
  fi
  if render --values chart/values.example.yaml --set gateway.proxy.httpTargetPort=8080 >"${tmp}/wrong-port.yaml"; then
    echo "❌ mismatched generated-proxy targetPort rendered successfully" >&2
    exit 1
  fi
  ;;
gateway-health)
  render --values chart/values.example.yaml >"${tmp}/health.yaml"
  yq eval-all -o=json '.' "${tmp}/health.yaml" | jq -s -e 'map(select(.kind == "HTTPRoute"))[0] as $r | $r.metadata.name == "platinum-health" and $r.spec.parentRefs[0].name == "platinum-gateway" and $r.spec.rules[0].matches[0].path.type == "Exact" and $r.spec.rules[0].matches[0].path.value == "/healthz" and $r.spec.rules[0].backendRefs[0].name == "platinum-api" and $r.spec.rules[0].backendRefs[0].port == 9898' >/dev/null
  yq eval-all 'select(.kind != "HTTPRoute")' "${tmp}/health.yaml" >"${tmp}/missing-health-route.yaml"
  if yq eval-all -o=json '.' "${tmp}/missing-health-route.yaml" | jq -s -e 'map(select(.kind == "HTTPRoute")) | length == 1' >/dev/null; then
    echo "❌ missing health HTTPRoute passed the route contract" >&2
    exit 1
  fi
  yq eval-all 'select(.kind == "HTTPRoute") | .spec.rules[0].backendRefs[0].port = 8080' "${tmp}/health.yaml" >"${tmp}/broken-health.yaml"
  if yq eval-all -o=json '.' "${tmp}/broken-health.yaml" | jq -s -e 'map(select(.kind == "HTTPRoute"))[0] | .spec.rules[0].matches[0].path.type == "Exact" and .spec.rules[0].matches[0].path.value == "/healthz" and .spec.rules[0].backendRefs[0].name == "platinum-api" and .spec.rules[0].backendRefs[0].port == 9898' >/dev/null; then
    echo "❌ corrupted health backend route passed the fixed contract" >&2
    exit 1
  fi
  ;;
registered-cert)
  render --values chart/values.example.yaml >"${tmp}/certs.yaml"
  yq eval-all -o=json '.' "${tmp}/certs.yaml" | jq -s -e '
    (map(select(.kind == "Certificate"))) as $certs |
    (map(select(.kind == "Gateway"))[0]) as $gateway |
    ($certs | map({key: .spec.commonName, value: .spec.secretName}) | from_entries) as $secrets |
    ($certs | length) == 2 and
    all($certs[]; . as $cert | $cert.spec.issuerRef.kind == "ClusterIssuer" and $cert.spec.issuerRef.name == "zinc-wildcard-letsencrypt" and ($cert.spec.commonName | startswith("*.")) and ($cert.spec.dnsNames | index($cert.spec.commonName) != null)) and
    ([$gateway.spec.listeners[] | select(.protocol == "HTTPS")] | length) == 2 and
    all($gateway.spec.listeners[] | select(.protocol == "HTTPS"); .tls.mode == "Terminate" and (.tls.certificateRefs | length) == 1 and .tls.certificateRefs[0].kind == "Secret" and .tls.certificateRefs[0].name == $secrets[.hostname])
  ' >/dev/null
  if render --values chart/values.example.yaml --set-json 'registeredCertificates.primary.dnsNames=["atomi.cloud"]' >"${tmp}/missing-san.yaml"; then
    echo "❌ wildcard Certificate without its wildcard SAN rendered successfully" >&2
    exit 1
  fi
  yq eval-all 'select(.kind == "Gateway") | (.spec.listeners[] | select(.name == "https-primary").tls.certificateRefs[0].name) = "wrong-secret"' "${tmp}/certs.yaml" >"${tmp}/broken-ref.yaml"
  if yq eval-all -o=json '.' "${tmp}/broken-ref.yaml" | jq -s -e '
    (map(select(.kind == "Certificate")) | map(.spec.secretName)) as $secrets |
    all(map(select(.kind == "Gateway"))[0].spec.listeners[] | select(.protocol == "HTTPS"); . as $listener | $listener.tls.mode == "Terminate" and ($secrets | index($listener.tls.certificateRefs[0].name) != null))
  ' >/dev/null; then
    echo "❌ broken HTTPS Certificate Secret reference passed the TLS contract" >&2
    exit 1
  fi
  ;;
entei-overlay)
  render --values chart/values.entei.yaml >"${tmp}/entei.yaml"
  yq eval-all -o=json '.' "${tmp}/entei.yaml" | jq -s -e '
    map(select(.kind != null) | {apiVersion, kind, name: .metadata.name}) | sort_by(.kind, .name) ==
    ([
      {apiVersion: "gateway.networking.k8s.io/v1", kind: "Gateway", name: "platinum-gateway"},
      {apiVersion: "gateway.networking.k8s.io/v1", kind: "GatewayClass", name: "platinum"},
      {apiVersion: "v1", kind: "Service", name: "platinum-edge"}
    ] | sort_by(.kind, .name))
  ' >/dev/null
  ;;
lb)
  render --values chart/values.example.yaml --values chart/values.digitalocean.yaml >"${tmp}/do.yaml"
  render --values chart/values.example.yaml --values chart/values.oci.yaml >"${tmp}/oci.yaml"
  render --values chart/values.example.yaml --values chart/values.aws.yaml >"${tmp}/aws.yaml"
  yq eval-all -o=json '.' "${tmp}/do.yaml" | jq -s -e 'map(select(.kind == "Service" and .metadata.name == "platinum-edge"))[0] | .spec.type == "LoadBalancer" and (.spec.selector | length) == 3 and ([.spec.ports[].targetPort] | sort) == [80, 443] and .metadata.annotations["service.beta.kubernetes.io/aws-load-balancer-eip-allocations"] == null and .metadata.annotations["oci.oraclecloud.com/reserved-ips"] == null' >/dev/null
  yq eval-all -o=json '.' "${tmp}/oci.yaml" | jq -s -e 'map(select(.kind == "Service" and .metadata.name == "platinum-edge"))[0] | .metadata.annotations["oci.oraclecloud.com/reserved-ips"] != null and (.metadata.annotations["oci.oraclecloud.com/reserved-ips"] | length) > 0' >/dev/null
  yq eval-all -o=json '.' "${tmp}/aws.yaml" | jq -s -e 'map(select(.kind == "Service" and .metadata.name == "platinum-edge"))[0] | (.metadata.annotations["service.beta.kubernetes.io/aws-load-balancer-subnets"] | split(",") | length) > 0 and (.metadata.annotations["service.beta.kubernetes.io/aws-load-balancer-eip-allocations"] | split(",") | length) == (.metadata.annotations["service.beta.kubernetes.io/aws-load-balancer-subnets"] | split(",") | length)' >/dev/null
  ! rg -n 'nodePort:|hostPort:' "${tmp}/do.yaml" "${tmp}/oci.yaml" "${tmp}/aws.yaml"
  yq eval-all 'select(.kind == "Service" and .metadata.name == "platinum-edge") | del(.metadata.annotations."service.beta.kubernetes.io/aws-load-balancer-eip-allocations")' "${tmp}/aws.yaml" >"${tmp}/aws-missing.yaml"
  if yq eval-all -o=json '.' "${tmp}/aws-missing.yaml" | jq -s -e 'map(select(.kind == "Service" and .metadata.name == "platinum-edge"))[0].metadata.annotations["service.beta.kubernetes.io/aws-load-balancer-eip-allocations"] != null' >/dev/null; then
    echo "❌ AWS overlay without its EIP annotation passed provider conformance" >&2
    exit 1
  fi
  yq eval-all 'select(.kind == "Service" and .metadata.name == "platinum-edge") | del(.metadata.annotations."oci.oraclecloud.com/reserved-ips")' "${tmp}/oci.yaml" >"${tmp}/oci-missing.yaml"
  if yq eval-all -o=json '.' "${tmp}/oci-missing.yaml" | jq -s -e 'map(select(.kind == "Service" and .metadata.name == "platinum-edge"))[0].metadata.annotations["oci.oraclecloud.com/reserved-ips"] != null' >/dev/null; then
    echo "❌ OCI overlay without its reserved-IP annotation passed provider conformance" >&2
    exit 1
  fi
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
  test -s chart/values.aws.yaml
  test -s chart/values.oci.yaml
  test -s chart/values.digitalocean.yaml
  test -s tests/fixtures/kgateway-v2.2.9-proxy-render.yaml
  test -s tests/fixtures/gateway-api-standard-channel-v1.6.0.yaml
  test -s policies/vap/workload-baseline.yaml
  test -s policies/vap/service-baseline.yaml
  ;;
tokenization-presence)
  rg -q '^## Tokenization surface$' docs/developer/platinum-baseline.md
  rg -q 'repository-qualified physical instance id' docs/developer/platinum-baseline.md
  rg -q 'upstream chart name/version/repository' docs/developer/platinum-baseline.md
  ;;
gateway-api-crd-fixture)
  # RB-244 regression guard: the standard-channel Gateway API CRDs must be
  # vendored, non-empty, checksum-pinned, and parse as the expected CRDs. This
  # mode would have caught the 404 — before the repair no local fixture existed
  # and the proof fetched a live, renameable upstream release URL.
  fixture_path="$(bash ./scripts/local/gateway-api-crd-fixture.sh verify)"
  pinned_version="$(bash ./scripts/local/gateway-api-crd-fixture.sh version)"
  case "${fixture_path}" in
  */"gateway-api-standard-channel-${pinned_version}.yaml") ;;
  *)
    echo "❌ fixture path does not embed pinned version ${pinned_version}" >&2
    exit 1
    ;;
  esac
  yq eval-all -o=json '.' "${fixture_path}" | jq -s -e '
    [.[].metadata.name] as $names |
    ($names | index("gatewayclasses.gateway.networking.k8s.io")) != null and
    ($names | index("gateways.gateway.networking.k8s.io")) != null and
    ($names | index("httproutes.gateway.networking.k8s.io")) != null and
    ([.[].kind] | any(. == "CustomResourceDefinition"))
  ' >/dev/null
  # The proof must apply the checksum-pinned fixture, never a live external URL.
  rg -q 'gateway-api-crd-fixture\.sh verify' scripts/validate/platinum-k3d.sh
  if rg -q 'https?://[^[:space:]]*gateway-api[^[:space:]]*channel\.yaml' scripts/validate/platinum-k3d.sh; then
    echo "❌ platinum-k3d proof still references a live Gateway API channel URL" >&2
    exit 1
  fi
  ;;
kgateway-crd-apply)
  # RB-295 regression guard: the rendered kgateway-crds-v2.2.9 fallback (after
  # `||`) must apply server-side with the stable field manager. Client-side
  # apply persists the whole manifest into the last-applied-configuration
  # annotation, and the archive's GatewayParameters CRD exceeds Kubernetes'
  # 262144-byte annotation limit, so the fallback failed before any Platinum
  # install. Static assertion only — no k3d or live provider work.
  fallback="$(rg -o -- '\|\|.*helm template kgateway-crds.*' scripts/validate/platinum-k3d.sh || true)"
  if [ -z "${fallback}" ]; then
    echo "❌ kgateway-crds rendered fallback pipeline not found in platinum-k3d.sh" >&2
    exit 1
  fi
  if ! printf '%s\n' "${fallback}" | rg -q -- 'kgateway-crds-v2\.2\.9\.tgz'; then
    echo "❌ kgateway-crds rendered fallback does not render the pinned v2.2.9 archive" >&2
    exit 1
  fi
  if ! printf '%s\n' "${fallback}" | rg -q -- '--server-side'; then
    echo "❌ kgateway-crds rendered fallback does not use server-side apply" >&2
    exit 1
  fi
  if ! printf '%s\n' "${fallback}" | rg -q -- '--field-manager=platinum-k3d-proof'; then
    echo "❌ kgateway-crds rendered fallback missing stable field manager platinum-k3d-proof" >&2
    exit 1
  fi
  ;;
*)
  echo "❌ unknown validation mode '${mode}'" >&2
  exit 1
  ;;
esac

echo "✅ Platinum ${mode} validation passed"
