#!/usr/bin/env bash
set -euo pipefail

mode="${1:-}"
release="${RELEASE:-helm-wrapper}"
namespace="${NAMESPACE:-sample}"
tmp="$(mktemp -d)"
trap 'rm -rf "${tmp}"' EXIT

[ -z "${mode}" ] && echo "❌ validation mode not set" >&2 && exit 1

bash ./scripts/local/vendor-chart-config.sh >/dev/null

# Assert that rendering the example values with the extra arguments fails, and fails for
# the intended reason: a refusal that reports some other diagnostic is a false pass.
refuses() {
  local refusal_label="$1"
  local reason="$2"
  local output
  shift 2
  if output="$(helm template "${release}" chart --namespace "${namespace}" --values chart/values.example.yaml "$@" 2>&1)"; then
    echo "❌ ${refusal_label} was accepted" >&2
    exit 1
  fi
  if ! grep -qF "${reason}" <<<"${output}"; then
    echo "❌ ${refusal_label} was refused for the wrong reason; expected '${reason}'" >&2
    printf '%s\n' "${output}" >&2
    exit 1
  fi
}

case "${mode}" in
schema)
  helm lint --strict chart --namespace "${namespace}" >/dev/null
  helm lint --strict chart --namespace "${namespace}" --values chart/values.example.yaml >/dev/null
  helm lint --strict chart --namespace "${namespace}" --values chart/values.example.yaml --values chart/values.lapras.yaml >/dev/null
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
  # Every object each stack owns, keyed by kind/name. Naming them is what keeps the
  # projection assertion non-vacuous: an object that stops rendering, or is renamed,
  # is reported as missing instead of quietly shrinking coverage to whatever
  # survived. The landscape overlay alone renders thirteen CR-bearing objects; the
  # cluster overlay disables the custom resources and leaves six.
  example_objects='["ConfigMap/wrapper-config","ConfigMap/wrapper-contracts","Service/wrapper-gateway","Service/wrapper-api","Deployment/wrapper-api","CloudflareDeploy/wrapper-edge","ExternalSecret/wrapper-secrets","HTTPRoute/wrapper-webhooks","LogtoApp/wrapper-identityexample","PlatformDependency/wrapper-dependencies","Problem/wrapper-problems","VirtualLandscapeService/wrapper-vls","Job/wrapper-migration"]'
  lapras_objects='["ConfigMap/wrapper-config","ConfigMap/wrapper-contracts","Service/wrapper-gateway","Service/wrapper-api","Deployment/wrapper-api","Job/wrapper-migration"]'
  # The cluster slot is contributed by the cluster overlay only, so the landscape
  # stack must not be asked for it and the stacked one must be.
  example_projection='{"platform":"sample","service":"wrapper","layer":"2","landscape":"example"}'
  lapras_projection='{"platform":"sample","service":"wrapper","layer":"2","landscape":"example","cluster":"lapras"}'

  # Assert the service-tree projection per rendered object, in both the labels and
  # the annotations, under the prefix in force. The module slot is resolved per
  # resource rather than once for the stack, because the stack is not one module:
  # the pinned upstream dependency renders wrapper-upstream* objects whose module is
  # "upstream" while every wrapper-owned object stays "api". A wrapper-owned object
  # must carry the whole projection; an upstream object is checked against the same
  # per-slot truth for whatever prefixed keys it does carry, since how much of the
  # projection reaches a third-party subchart is that dependency's interface, not
  # this gate's. Anything that is neither is reported, so a new wrapper resource
  # cannot slip out of coverage by simply not being on the list.
  carries_projection() {
    local description="$1" file="$2" prefix="$3" forbidden="$4" objects="$5" projection="$6"
    local offenders
    offenders="$(yq eval-all -o=json '.' "${file}" | jq -s -r \
      --arg prefix "${prefix}" --arg forbidden "${forbidden}" \
      --argjson objects "${objects}" --argjson projection "${projection}" '
        def slot($key): "\($prefix)/\($key)";
        def stale($id; $keys): select($forbidden != "")
          | $keys[] | select(startswith("\($forbidden)/")) | "\($id): stale key \(.)";
        map(select(.kind != null)) as $rendered
        | ($rendered | map("\(.kind)/\(.metadata.name)")) as $ids
        | [ (if ($rendered | length) == 0 then "no object rendered" else empty end)
          , (($objects - $ids)[] | "missing object \(.)")
          , ( $rendered[]
              | "\(.kind)/\(.metadata.name)" as $id
              | (.metadata.labels // {}) as $labels
              | (.metadata.annotations // {}) as $annotations
              | (($labels | keys) + ($annotations | keys)) as $keys
              | if ($objects | index($id)) then
                  ( ( ($projection + {module: "api"}) | to_entries[]
                      | select($labels[slot(.key)] != .value or $annotations[slot(.key)] != .value)
                      | "\($id): \(slot(.key)) label=\($labels[slot(.key)] // "absent") annotation=\($annotations[slot(.key)] // "absent") want=\(.value)" )
                  , stale($id; $keys) )
                elif (.metadata.name | startswith("wrapper-upstream")) then
                  ( select($keys | any(startswith("\($prefix)/")))
                    | ( ( ($projection + {module: "upstream"}) | to_entries[]
                          | select(($labels[slot(.key)] // .value) != .value or ($annotations[slot(.key)] // .value) != .value)
                          | "\($id): \(slot(.key)) label=\($labels[slot(.key)] // "absent") annotation=\($annotations[slot(.key)] // "absent") want=\(.value)" )
                      , stale($id; $keys) ) )
                else
                  "\($id): neither a wrapper-owned object nor a wrapper-upstream dependency object"
                end ) ] | .[]')"
    if [ -n "${offenders}" ]; then
      echo "❌ ${description}" >&2
      printf '%s\n' "${offenders}" >&2
      exit 1
    fi
  }

  helm template "${release}" chart --namespace "${namespace}" --values chart/values.example.yaml >"${tmp}/example.yaml"
  helm template "${release}" chart --namespace "${namespace}" --values chart/values.example.yaml --values chart/values.lapras.yaml >"${tmp}/lapras.yaml"
  helm template "${release}" chart --namespace "${namespace}" --values chart/values.example.yaml --set labelPrefix=example.dev >"${tmp}/example-override.yaml"
  helm template "${release}" chart --namespace "${namespace}" --values chart/values.example.yaml --values chart/values.lapras.yaml --set labelPrefix=example.dev >"${tmp}/lapras-override.yaml"

  carries_projection "the example stack projection" "${tmp}/example.yaml" atomi.cloud '' "${example_objects}" "${example_projection}"
  carries_projection "the example+lapras stack projection" "${tmp}/lapras.yaml" atomi.cloud '' "${lapras_objects}" "${lapras_projection}"
  # The override runs re-assert the same per-object truth under the new prefix and
  # additionally require that no key under the default prefix survives, so an
  # override that merely adds keys cannot pass.
  carries_projection "the example stack prefix override" "${tmp}/example-override.yaml" example.dev atomi.cloud "${example_objects}" "${example_projection}"
  carries_projection "the example+lapras stack prefix override" "${tmp}/lapras-override.yaml" example.dev atomi.cloud "${lapras_objects}" "${lapras_projection}"
  ;;
reloader)
  helm template "${release}" chart --namespace "${namespace}" --values chart/values.example.yaml >"${tmp}/default.yaml"
  yq eval-all -o=json '.' "${tmp}/default.yaml" | jq -s -e 'map(select(.kind == "Deployment" or .kind == "StatefulSet" or .kind == "DaemonSet" or .kind == "Job")) | length > 0 and all(.[]; .metadata.annotations["reloader.stakater.com/auto"] == "true")' >/dev/null
  helm template "${release}" chart --namespace "${namespace}" --values chart/values.example.yaml --set workload.reloader.enabled=false >"${tmp}/optout.yaml"
  # The opt-out is scoped to the wrapper workload, so name it: the pinned upstream
  # dependency renders a second Deployment and a positional pick would now read
  # that one instead. Every other workload must still carry the annotation, or an
  # opt-out that switched reloader off everywhere would read as a pass.
  yq eval-all -o=json '.' "${tmp}/optout.yaml" | jq -s -e 'map(select(.kind == "Deployment" or .kind == "StatefulSet" or .kind == "DaemonSet" or .kind == "Job")) as $workloads | ($workloads | map(select(.kind == "Deployment" and .metadata.name == "wrapper-api")) | length == 1 and .[0].metadata.annotations["reloader.stakater.com/auto"] == null) and ($workloads | map(select(.metadata.name != "wrapper-api")) | length > 0 and all(.[]; .metadata.annotations["reloader.stakater.com/auto"] == "true"))' >/dev/null
  ;;
secret)
  helm template "${release}" chart --namespace "${namespace}" --values chart/values.example.yaml --set secret.enabled=true >"${tmp}/secret.yaml"
  yq eval-all -o=json '.' "${tmp}/secret.yaml" | jq -s -e 'map(select(.kind == "ExternalSecret"))[0] as $secret | $secret.metadata.name == "wrapper-secrets" and $secret.spec.target.name == "wrapper" and ($secret.spec.data == null) and $secret.spec.dataFrom[0].rewrite[0].regexp.target == "SHARED_$1" and $secret.spec.dataFrom[1].rewrite[0].regexp.target == "WRAPPER_$1"' >/dev/null
  refuses "a colliding secret folder prefix" "collide on prefix" --set secret.enabled=true --set-string secret.sharedFolder=/wrapper
  refuses "a service folder that diverges from the service name" "must end in the service name" --set secret.enabled=true --set-string secret.serviceFolder=/billing
  ;;
fullname)
  helm template "${release}" chart --namespace "${namespace}" --values chart/values.example.yaml >"${tmp}/names.yaml"
  yq eval-all -o=json '.' "${tmp}/names.yaml" | jq -s -e 'map(select(.kind != null) | .metadata.name) | length > 0 and all(.[]; test("^[a-z0-9]+-[a-z0-9]+$"))' >/dev/null
  yq -e '.upstream.fullnameOverride | test("^[a-z0-9]+-[a-z0-9]+$")' chart/values.yaml >/dev/null
  helm template "${release}" chart --namespace "${namespace}" --values chart/values.example.yaml --set serviceTree.module=maincache --set fullnameOverride=wrapper-maincache >"${tmp}/maincache.yaml"
  # Select the renamed workload by name. The pinned upstream dependency renders a
  # second Deployment of its own, so a positional pick would assert against
  # whichever Deployment happened to sort first; the old wrapper name must also be
  # gone, or a rename that only added an object would still pass.
  yq eval-all -o=json '.' "${tmp}/maincache.yaml" | jq -s -e 'map(select(.kind == "Deployment")) as $deployments | ($deployments | map(select(.metadata.name == "wrapper-maincache")) | length == 1 and .[0].metadata.labels["atomi.cloud/module"] == "maincache") and ($deployments | any(.metadata.name == "wrapper-api") | not)' >/dev/null
  refuses "a module/fullname mismatch" 'fullnameOverride must be "wrapper-maincache"' --set serviceTree.module=maincache
  ;;
primordial)
  helm template "${release}" chart --namespace "${namespace}" --values chart/values.example.yaml --set primordial.enabled=true >"${tmp}/primordial.yaml"
  kubeconform -strict -summary -schema-location default -schema-location 'schemas/{{ .ResourceKind }}.json' "${tmp}/primordial.yaml"
  yq eval-all -o=json '.' "${tmp}/primordial.yaml" | jq -s -e 'map(select(.kind == "PlatformDependency"))[0].spec as $spec | [$spec.database, $spec.kv, $spec.cache, $spec.store] | map(. // {}) | add | to_entries | all(.[]; (.value.engine | keys) == [.value.type])' >/dev/null
  ! rg -n '(^|[[:space:]])(share|sharedVia|redirectUris|desiredVersion):' "${tmp}/primordial.yaml"
  ;;
lpsm)
  digest=7527f8ce8af22ee78eaaeaa68d24857bf88c3c5a8a9d2fd812f607441cfbca7d
  other=8cd31a396907eae9357fd730e605e0a8e8f6fb82dddcfc57819f44c00c9f1531
  petname=otter-beats-potato
  zone=kube.entei.dev.atomi.cloud
  contracts='select(.kind == "ConfigMap" and .metadata.name == "wrapper-contracts")'

  helm template "${release}" chart --namespace "${namespace}" --values chart/values.example.yaml >"${tmp}/lpsm.yaml"
  ordinary="$(yq -r "${contracts} | .data.\"lpsm.ordinaryHostname\"" "${tmp}/lpsm.yaml")"
  instance="$(yq -r "${contracts} | .data.\"lpsm.instanceHostname\"" "${tmp}/lpsm.yaml")"
  parsed="$(yq -r "${contracts} | .data.\"lpsm.parsed\"" "${tmp}/lpsm.yaml")"
  original="$(yq -r "${contracts} | .data.\"instance.original\"" "${tmp}/lpsm.yaml")"
  label="$(yq -r "${contracts} | .data.\"instance.label\"" "${tmp}/lpsm.yaml")"
  expected_original="$(yq -r '.instance.original' chart/values.yaml)"
  [ "${ordinary}" != "api.wrapper.sample.example.cluster.atomi.cloud" ] && echo "❌ ordinary LPSM hostname mismatch" >&2 && exit 1
  [ "${instance}" != "api.wrapper.sample.run001.example.local.example.invalid" ] && echo "❌ instance LPSM hostname mismatch" >&2 && exit 1
  jq -e '.landscape == "example" and .platform == "sample" and .service == "wrapper" and .module == "api" and .instance == "run001"' <<<"${parsed}" >/dev/null
  [ "${original}" != "${expected_original}" ] && echo "❌ recorded instance original does not equal the supplied value" >&2 && exit 1
  [ "${label}" != "${expected_original}" ] && echo "❌ recorded instance label does not equal the authorized minter value" >&2 && exit 1

  # Accepted coordinates outside the ENTEI dev zone. Each proves the same five-slot
  # dotted derivation and its parse round-trip in a different canonical zone, with
  # the platform slot still taken from the release namespace rather than a values
  # file — the refusal below proves the negative half of that same rule.
  accepts_coordinate() {
    local description="$1" expected_hostname="$2" expected_parse="$3"
    shift 3
    local hostname parse
    helm template "${release}" chart --namespace "${namespace}" --values chart/values.example.yaml "$@" >"${tmp}/accepted.yaml"
    hostname="$(yq -r "${contracts} | .data.\"lpsm.instanceHostname\"" "${tmp}/accepted.yaml")"
    parse="$(yq -r "${contracts} | .data.\"lpsm.parsed\"" "${tmp}/accepted.yaml")"
    if [ "${hostname}" != "${expected_hostname}" ]; then
      echo "❌ ${description}: expected '${expected_hostname}', got '${hostname}'" >&2
      exit 1
    fi
    if [ "${parse}" != "${expected_parse}" ]; then
      echo "❌ ${description}: parse round-trip returned '${parse}'" >&2
      exit 1
    fi
  }

  accepts_coordinate "the ABSOL localhost coordinate" \
    api.wrapper.sample.run42.absol.localhost \
    '{"instance":"run42","landscape":"absol","module":"api","platform":"sample","service":"wrapper"}' \
    --set-string contracts.lpsm.landscape=absol \
    --set-string contracts.lpsm.instance=run42 \
    --set-string contracts.lpsm.instanceZone=localhost

  accepts_coordinate "the Boron lapras coordinate" \
    api.lithium.sample.kirin.lapras.admin.atomi.cloud \
    '{"instance":"kirin","landscape":"lapras","module":"api","platform":"sample","service":"lithium"}' \
    --set-string contracts.lpsm.service=lithium \
    --set-string contracts.lpsm.instance=kirin \
    --set-string contracts.lpsm.landscape=lapras \
    --set-string contracts.lpsm.instanceZone=admin.atomi.cloud

  helm template "${release}" chart --namespace "${namespace}" --values chart/values.example.yaml \
    --set instance.preview.enabled=true --set-string "contracts.lpsm.instanceZone=${zone}" >"${tmp}/preview.yaml"
  preview_host="$(yq -r "${contracts} | .data.\"preview.hostname\"" "${tmp}/preview.yaml")"
  [ "${preview_host}" != "api.wrapper.sample.${petname}.castform.${zone}" ] && echo "❌ preview coordinate mismatch" >&2 && exit 1

  helm template "${release}" chart --namespace "${namespace}" --values chart/values.example.yaml \
    --set instance.preview.enabled=true --set-string "contracts.lpsm.instanceZone=${zone}" \
    --set-string "instance.preview.canonical.previewPetname=${petname}-ekj" \
    --set-string "instance.preview.receipt.previewPetname=${petname}-ekj" \
    --set-string "instance.preview.receipt.collision.liveFullLeaseDigest=${other}" >"${tmp}/collision.yaml"
  collision_host="$(yq -r "${contracts} | .data.\"preview.hostname\"" "${tmp}/collision.yaml")"
  [ "${collision_host}" != "api.wrapper.sample.${petname}-ekj.castform.${zone}" ] && echo "❌ live-collision petname mismatch" >&2 && exit 1

  refuses "an unverified canonical digest" "PreviewIdentityMismatch: canonical full digest" --set instance.preview.enabled=true --set-string "instance.preview.canonical.fullLeaseDigest=${other}"
  refuses "a caller-supplied collision suffix" "PreviewIdentityMismatch: collision suffix" --set instance.preview.enabled=true --set-string "instance.preview.canonical.previewPetname=${petname}-abc" --set-string "instance.preview.receipt.previewPetname=${petname}-abc" --set-string "instance.preview.receipt.collision.liveFullLeaseDigest=${other}"
  refuses "a same-digest collision" "same full digest is an idempotent join" --set instance.preview.enabled=true --set-string "instance.preview.canonical.previewPetname=${petname}-ekj" --set-string "instance.preview.receipt.previewPetname=${petname}-ekj" --set-string "instance.preview.receipt.collision.liveFullLeaseDigest=${digest}"
  refuses "an unresolved branch pin" "neither a released version nor a full commit" --set instance.preview.enabled=true --set-string 'instance.preview.manifest.pins.nitroso\.zinc=main'
  refuses "an unnormalized physical instance id" "does not match pattern" --set-string instance.original=repository-a:pr-123
  refuses "a dash-fused Garden hostname" "must use the canonical dotted LPSM form" --set-string contracts.lpsm.parseHostname=api-wrapper-sample-run001-example.local.example.invalid
  refuses "an uppercase parser input" "must be a lowercase DNS-1123 label" --set-string contracts.lpsm.parseHostname=API.wrapper.sample.run001.example.local.example.invalid
  ;;
lb)
  helm template "${release}" chart --namespace "${namespace}" --values chart/values.example.yaml --set gateway.provider=digitalocean >"${tmp}/do.yaml"
  helm template "${release}" chart --namespace "${namespace}" --values chart/values.example.yaml --set gateway.provider=oci --set-string gateway.oci.reservedPublicIp=203.0.113.10 >"${tmp}/oci.yaml"
  helm template "${release}" chart --namespace "${namespace}" --values chart/values.example.yaml --set gateway.provider=aws --set-string 'gateway.aws.subnetIds[0]=subnet-a' --set-string 'gateway.aws.subnetIds[1]=subnet-b' --set-string 'gateway.aws.eipAllocationIds[0]=eipalloc-a' --set-string 'gateway.aws.eipAllocationIds[1]=eipalloc-b' >"${tmp}/aws.yaml"
  yq eval-all -o=json '.' "${tmp}/do.yaml" | jq -s -e 'map(select(.kind == "Service" and .metadata.name == "wrapper-gateway")) | length == 1 and (.[0] | .spec.type == "LoadBalancer" and .metadata.annotations["service.beta.kubernetes.io/aws-load-balancer-eip-allocations"] == null and .metadata.annotations["oci.oraclecloud.com/reserved-ips"] == null)' >/dev/null
  yq eval-all -o=json '.' "${tmp}/oci.yaml" | jq -s -e 'map(select(.kind == "Service" and .metadata.name == "wrapper-gateway")) | length == 1 and .[0].metadata.annotations["oci.oraclecloud.com/reserved-ips"] == "203.0.113.10"' >/dev/null
  yq eval-all -o=json '.' "${tmp}/aws.yaml" | jq -s -e 'map(select(.kind == "Service" and .metadata.name == "wrapper-gateway")) | length == 1 and (.[0] | .metadata.annotations["service.beta.kubernetes.io/aws-load-balancer-subnets"] == "subnet-a,subnet-b" and .metadata.annotations["service.beta.kubernetes.io/aws-load-balancer-eip-allocations"] == "eipalloc-a,eipalloc-b")' >/dev/null
  ! rg -n 'nodePort:|hostPort:' "${tmp}/do.yaml" "${tmp}/oci.yaml" "${tmp}/aws.yaml"
  ;;
task-surface)
  task --list-all | rg -q 'example:lapras:debug'
  task --list-all | rg -q 'example:lapras:template'
  task --list-all | rg -q 'example:lapras:install'
  task --list-all | rg -q 'example:lapras:remove'
  task example:lapras:template | rg -q '^kind: Deployment$'
  task example:lapras:debug >/dev/null
  ;;
vap-interface)
  bash ./scripts/validate/vap-interface.sh
  ;;
rendered-manifests)
  vap_definitions="${VAP_DEFINITIONS:-policies/vap}"
  if [ "$(realpath -m "${vap_definitions}")" = "$(realpath -m policies/vap)" ]; then
    bash ./scripts/validate/vap-interface.sh >/dev/null
  fi
  if [ -f "${vap_definitions}" ]; then
    vap_definition_files=("${vap_definitions}")
  elif [ -d "${vap_definitions}" ]; then
    mapfile -t vap_definition_files < <(find "${vap_definitions}" -maxdepth 1 -type f -name '*.yaml' -print | sort)
  else
    echo "❌ VAP_DEFINITIONS is neither a file nor a directory: ${vap_definitions}" >&2
    exit 1
  fi
  [ "${#vap_definition_files[@]}" -eq 0 ] && echo "❌ VAP_DEFINITIONS contains no policy definitions: ${vap_definitions}" >&2 && exit 1
  # Filter by the API groups the pinned resourceRules name, never by kind: a group-level
  # filter keeps whatever kinds those rules grow into, while still excluding the custom
  # resources whose GVRs kyverno cannot resolve offline.
  policy_groups="$(for policy in "${vap_definition_files[@]}"; do yq -r '.spec.matchConstraints.resourceRules[].apiGroups[]' "${policy}"; done | sort -u | jq -Rsc 'split("\n") | .[0:-1] | unique')"
  # The landscape and cluster overlays disable objects the base stack renders, so every
  # stack is rendered, schema-checked, and policy-checked in its own right.
  for stack in base example example+lapras; do
    case "${stack}" in
    base) stack_values=() ;;
    example) stack_values=(--values chart/values.example.yaml) ;;
    example+lapras) stack_values=(--values chart/values.example.yaml --values chart/values.lapras.yaml) ;;
    esac
    echo "📝 Validating the ${stack} value stack"
    helm template "${release}" chart --namespace "${namespace}" "${stack_values[@]}" >"${tmp}/${stack}.yaml"
    kubeconform -strict -summary -schema-location default -schema-location 'schemas/{{ .ResourceKind }}.json' "${tmp}/${stack}.yaml"
    yq eval-all -o=json '.' "${tmp}/${stack}.yaml" | jq -s --argjson groups "${policy_groups}" 'map(select(.kind != null) | select((.apiVersion | split("/") | if length == 1 then "" else .[0] end) as $group | $groups | index($group)))' | yq -P '.[] | split_doc' >"${tmp}/vap-${stack}.yaml"
    yq eval-all -o=json '.' "${tmp}/vap-${stack}.yaml" | jq -s -e 'length > 0' >/dev/null
    kyverno apply "${vap_definition_files[@]}" --resource "${tmp}/vap-${stack}.yaml" --detailed-results --remove-color
    # Re-run one definition at a time: the aggregate summary stays green when a single
    # definition silently stops matching anything, so each one must report its own pass.
    for policy in "${vap_definition_files[@]}"; do
      if ! kyverno apply "${policy}" --resource "${tmp}/vap-${stack}.yaml" --detailed-results --remove-color --warn-no-pass --warn-exit-code 1; then
        echo "❌ '${policy}' rejected or matched no ${stack} stack resource" >&2
        exit 1
      fi
    done
    echo "🔐 Every pinned definition passed at least one ${stack} stack resource"
  done
  ;;
publish-git)
  PUBLISH_MODE=git PUBLISH_DRY_RUN=true RELEASE_VERSION=v0.1.0 PUBLISH_OUTPUT_DIR="${tmp}/git" bash ./scripts/ci/publish.sh >/dev/null
  [ ! -s "${tmp}/git/diene-helm-wrapper-0.1.0.tgz" ] && echo "❌ git chart package missing" >&2 && exit 1
  [ ! -s "${tmp}/git/index.yaml" ] && echo "❌ git chart index missing" >&2 && exit 1
  helm template "${release}" "${tmp}/git/diene-helm-wrapper-0.1.0.tgz" --namespace "${namespace}" --values chart/values.example.yaml >"${tmp}/packaged.yaml"
  yq eval-all -o=json '.' "${tmp}/packaged.yaml" | jq -s -e 'map(select(.kind == "ConfigMap" and .metadata.name == "wrapper-config")) | (length == 1) and (.[0].data | has("application.yaml") and has("application.example.yaml"))' >/dev/null
  ;;
publish-oci)
  OCI_REGISTRY=ghcr.io OCI_REPOSITORY=atomicloud/diene.all PUBLISH_MODE=oci PUBLISH_DRY_RUN=true RELEASE_VERSION=v0.1.0 PUBLISH_OUTPUT_DIR="${tmp}/oci" bash ./scripts/ci/publish.sh >/dev/null
  [ ! -s "${tmp}/oci/diene-helm-wrapper-0.1.0.tgz" ] && echo "❌ OCI chart package missing" >&2 && exit 1
  rg -q '^oci://ghcr.io/atomicloud/diene.all$' "${tmp}/oci/oci-ref.txt"
  if output="$(OCI_REGISTRY=ghcr.io OCI_REPOSITORY=AtomiCloud/diene.all PUBLISH_MODE=oci PUBLISH_DRY_RUN=true RELEASE_VERSION=v0.1.0 PUBLISH_OUTPUT_DIR="${tmp}/uppercase" bash ./scripts/ci/publish.sh 2>&1)"; then
    echo "❌ an uppercase OCI repository was accepted" >&2
    exit 1
  fi
  grep -qF 'OCI_REPOSITORY must be lowercase' <<<"${output}"
  ;;
version)
  PUBLISH_MODE=git PUBLISH_DRY_RUN=true RELEASE_VERSION=v0.1.0 PUBLISH_OUTPUT_DIR="${tmp}/version" bash ./scripts/ci/publish.sh >/dev/null
  ;;
presence)
  test -s docs/developer/helm-wrapper-baseline.md
  test -s .claude/skills/helm-wrapper/SKILL.md
  test -s chart/templates/webhook-route.yaml
  test -s chart/templates/contracts.yaml
  test -s policies/vap-interface.json
  test -s policies/vap/vanadium-disallowlatest.yaml
  test -s probes/features.json
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
