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
  # The wrapper redefines two named templates the pinned dependency owns —
  # bjw-s.common.lib.metadata.globalLabels/globalAnnotations — because upstream
  # binds `$name := $k` and only `tpl`-renders the VALUE, so a map KEY reaches
  # every rendered upstream object verbatim and no prefix override could move it.
  # That override is sound only while the dependency still owns those two names
  # and still leaves its own keys un-templated, so the interface is asserted
  # before any projection is: a bump that renames them would make the wrapper
  # redefine nothing and silently drop every upstream service-tree key, and a
  # bump that starts templating them would make the override redundant. Either
  # way the answer is to re-measure, not to keep asserting against a stale pin.
  upstream_version="$(yq -r '.dependencies[] | select(.alias == "upstream") | .version' chart/Chart.yaml)"
  measured_upstream_version=5.0.1
  if [ "${upstream_version}" != "${measured_upstream_version}" ]; then
    echo "❌ the pinned upstream dependency is ${upstream_version}, but the metadata-template override was measured against ${measured_upstream_version}" >&2
    exit 1
  fi
  mkdir -p "${tmp}/upstream"
  tar -xzf "chart/charts/app-template-${upstream_version}.tgz" -C "${tmp}/upstream"
  for template in globalLabels globalAnnotations; do
    definition="${tmp}/upstream/app-template/charts/common/templates/lib/metadata/_${template}.tpl"
    if [ ! -s "${definition}" ]; then
      echo "❌ the pinned dependency no longer carries lib/metadata/_${template}.tpl; re-measure the wrapper's override" >&2
      exit 1
    fi
    grep -qF "define \"bjw-s.common.lib.metadata.${template}\"" "${definition}" || {
      echo "❌ the pinned dependency no longer defines bjw-s.common.lib.metadata.${template}; re-measure the wrapper's override" >&2
      exit 1
    }
    # Go template text, not a shell expansion: the single quotes are what keep the
    # measured `$name := $k` binding literal.
    # shellcheck disable=SC2016
    grep -qF '$name := $k' "${definition}" || {
      echo "❌ the pinned dependency no longer binds its ${template} map key verbatim; the wrapper's override may now be redundant or wrong" >&2
      exit 1
    }
    grep -qF "define \"bjw-s.common.lib.metadata.${template}\"" chart/templates/_helpers.tpl || {
      echo "❌ the wrapper no longer redefines bjw-s.common.lib.metadata.${template}; an upstream metadata key would stop following labelPrefix" >&2
      exit 1
    }
  done

  # Every object each stack owns, keyed by kind/name, split by the module each one
  # projects. Naming them is what keeps the projection assertion non-vacuous: an
  # object that stops rendering, or is renamed, is reported as missing instead of
  # quietly shrinking coverage to whatever survived. The base and landscape stacks
  # each render thirteen wrapper-owned objects; the cluster overlay disables the
  # custom resources and leaves six. The pinned dependency's two objects are named
  # in their own list, so an upstream Deployment or Service that stopped rendering
  # can no longer make the upstream half of this gate assert nothing.
  base_objects='["ConfigMap/wrapper-config","ConfigMap/wrapper-contracts","Service/wrapper-gateway","Service/wrapper-api","Deployment/wrapper-api","CloudflareDeploy/wrapper-edge","ExternalSecret/wrapper-secrets","HTTPRoute/wrapper-webhooks","LogtoApp/wrapper-identityexample","PlatformDependency/wrapper-dependencies","Problem/wrapper-problems","VirtualLandscapeService/wrapper-vls","Job/wrapper-migration"]'
  example_objects="${base_objects}"
  lapras_objects='["ConfigMap/wrapper-config","ConfigMap/wrapper-contracts","Service/wrapper-gateway","Service/wrapper-api","Deployment/wrapper-api","Job/wrapper-migration"]'
  upstream_objects='["Deployment/wrapper-upstream","Service/wrapper-upstream"]'
  # Every object that owns a pod selector, named exactly. All three stacks render
  # all five, so a stack that stopped rendering one is reported rather than
  # narrowing the hook-isolation comparison to whatever survived.
  selector_objects='["Service/wrapper-api","Service/wrapper-gateway","Service/wrapper-upstream","Deployment/wrapper-api","Deployment/wrapper-upstream"]'
  hook_job=wrapper-migration
  hook_pod_name=wrapper-migration
  hook_component=migration
  # The landscape slot is contributed by the landscape overlay and the cluster slot
  # by the cluster overlay, so the base stack must be asked for neither, the
  # landscape stack for the first only, and the stacked one for both.
  base_projection='{"platform":"sample","service":"wrapper","layer":"2"}'
  example_projection='{"platform":"sample","service":"wrapper","layer":"2","landscape":"example"}'
  lapras_projection='{"platform":"sample","service":"wrapper","layer":"2","landscape":"example","cluster":"lapras"}'
  # The recorded physical instance pair is read from the values file rather than
  # pinned here, so the assertion tracks the authorized minter's values instead of a
  # copy. The two halves are DISTINCT — a repository-qualified original beside its
  # minted DNS-1123 label — so an implementation that stamped one half into both
  # annotations is reported instead of passing.
  instance_original="$(yq -r '.global.instance.original' chart/values.yaml)"
  instance_label="$(yq -r '.global.instance.label' chart/values.yaml)"
  if [ "${instance_original}" = "${instance_label}" ]; then
    echo "❌ the committed instance pair records the same bytes twice, so the annotation assertion below could not tell the halves apart" >&2
    exit 1
  fi
  physical_instance="$(jq -n --arg original "${instance_original}" --arg label "${instance_label}" '{"instance-original": $original, "instance-label": $label}')"
  # Under preview BOTH halves are the receipt-bound petname, because an
  # assembler-minted petname is already its own unshortened id. It is read from the
  # same values file for the same reason, and it must differ from both physical
  # halves or the preview stack below could not tell a stale physical annotation
  # apart from a correctly resolved preview one.
  preview_petname="$(yq -r '.global.instance.preview.receipt.previewPetname' chart/values.yaml)"
  if [ "${preview_petname}" = "${instance_original}" ] || [ "${preview_petname}" = "${instance_label}" ]; then
    echo "❌ the committed preview petname equals a physical half, so the preview stack could not detect a hard-coded physical identity" >&2
    exit 1
  fi
  preview_instance="$(jq -n --arg petname "${preview_petname}" '{"instance-original": $petname, "instance-label": $petname}')"

  # Assert the service-tree projection per rendered object, in both the labels and
  # the annotations, under the prefix in force. The module slot is resolved per
  # resource rather than once for the stack, because the stack is not one module:
  # the pinned upstream dependency renders wrapper-upstream objects whose module is
  # "upstream" while every wrapper-owned object stays "api". Both families are then
  # held to the SAME rule — every slot present and exact in both maps, plus the
  # recorded instance pair in the annotations. The upstream family used to be
  # excused twice over: the whole check was skipped unless the object already
  # carried a key under the prefix in force, and each missing slot defaulted to its
  # own expected value. Under a prefix override an upstream object carried no such
  # key, so both escapes fired at once and the object was waved through with every
  # key still under the old prefix. Nothing is excused now, so an object outside
  # either named list is reported and a new wrapper resource cannot slip out of
  # coverage by simply not being on the list.
  projection_offenders() {
    local file="$1" prefix="$2" forbidden="$3" objects="$4" projection="$5" instance="$6"
    yq eval-all -o=json '.' "${file}" | jq -s -r \
      --arg prefix "${prefix}" --arg forbidden "${forbidden}" \
      --argjson instance "${instance}" \
      --argjson objects "${objects}" --argjson upstream "${upstream_objects}" --argjson projection "${projection}" '
        def slot($key): "\($prefix)/\($key)";
        map(select(.kind != null)) as $rendered
        | ($rendered | map("\(.kind)/\(.metadata.name)")) as $ids
        | [ (if ($rendered | length) == 0 then "no object rendered" else empty end)
          , ((($objects + $upstream) - $ids)[] | "missing object \(.)")
          , ( $rendered[]
              | "\(.kind)/\(.metadata.name)" as $id
              | (.metadata.labels // {}) as $labels
              | (.metadata.annotations // {}) as $annotations
              | (($labels | keys) + ($annotations | keys)) as $keys
              | (if ($objects | index($id)) then "api"
                 elif ($upstream | index($id)) then "upstream"
                 else null end) as $module
              | if $module == null then
                  "\($id): neither a named wrapper-owned object nor a named upstream dependency object"
                else
                  ( ( ($projection + {module: $module}) | to_entries[]
                      | select($labels[slot(.key)] != .value or $annotations[slot(.key)] != .value)
                      | "\($id): \(slot(.key)) label=\($labels[slot(.key)] // "absent") annotation=\($annotations[slot(.key)] // "absent") want=\(.value)" )
                  , ( $instance | to_entries[]
                      | select($annotations[slot(.key)] != .value)
                      | "\($id): \(slot(.key)) annotation=\($annotations[slot(.key)] // "absent") want=\(.value)" )
                  , ( select($forbidden != "")
                      | $keys[] | select(startswith("\($forbidden)/"))
                      | "\($id): stale key \(.)" ) )
                end ) ] | .[]'
  }

  carries_projection() {
    local description="$1"
    shift
    local offenders
    offenders="$(projection_offenders "$@")"
    if [ -n "${offenders}" ]; then
      echo "❌ ${description}" >&2
      printf '%s\n' "${offenders}" >&2
      exit 1
    fi
  }

  # The control half of the same assertion: a sabotaged render must produce at least
  # one offender. Without it a projection check that silently stopped selecting
  # anything would keep reporting a clean pass over nothing.
  rejects_projection() {
    local description="$1"
    shift
    if [ -z "$(projection_offenders "$@")" ]; then
      echo "❌ ${description}: the projection assertion accepted the sabotage" >&2
      exit 1
    fi
  }

  # A lifecycle hook pod must not be born wearing the primary workload's selector
  # identity. Both primary Service selectors and the Deployment's own matchLabels
  # are exactly the wrapper's selectorLabels, so a hook pod stamped with the full
  # label set is a strict SUPERSET of every one of them and is eligible for their
  # EndpointSlices while the hook runs; nothing routes today only because the
  # Services name `targetPort: http` and the migration container declares no port,
  # which is an accident of this sample rather than a property of the shape.
  #
  # The check is deliberately object-and-name-exact rather than a scan of whatever
  # happened to render: every named selector-bearing object must be present, must
  # carry a NON-EMPTY selector, and must fail to select the hook pod. A missing
  # object, an emptied selector, or a hook pod with no labels at all is an offender,
  # so this cannot pass by matching nothing.
  hook_offenders() {
    local file="$1" prefix="$2" projection="$3" instance="$4"
    yq eval-all -o=json '.' "${file}" | jq -s -r \
      --arg prefix "${prefix}" --arg job "${hook_job}" --arg name "${hook_pod_name}" --arg component "${hook_component}" \
      --argjson selectors "${selector_objects}" --argjson projection "${projection}" --argjson instance "${instance}" '
        def slot($key): "\($prefix)/\($key)";
        def selects($pod; $selector): ($selector | length) > 0
          and ([$selector | to_entries[] | select($pod[.key] == .value)] | length) == ($selector | length);
        map(select(.kind != null)) as $rendered
        | ($rendered | map("\(.kind)/\(.metadata.name)")) as $ids
        | ($rendered | map(select(.kind == "Job" and .metadata.name == $job))) as $jobs
        | ($jobs[0].spec.template.metadata.labels // {}) as $pod
        | ($jobs[0].spec.template.metadata.annotations // {}) as $podAnnotations
        | [ (if ($jobs | length) != 1 then "expected exactly one Job/\($job), found \($jobs | length)" else empty end)
          , (if ($pod | length) == 0 then "Job/\($job) renders a pod template with no labels at all" else empty end)
          , (if $pod["app.kubernetes.io/name"] != $name
              then "Job/\($job) pod app.kubernetes.io/name=\($pod["app.kubernetes.io/name"] // "absent") want=\($name)" else empty end)
          , (if $pod["app.kubernetes.io/component"] != $component
              then "Job/\($job) pod app.kubernetes.io/component=\($pod["app.kubernetes.io/component"] // "absent") want=\($component)" else empty end)
          , ( ($projection + {module: "api"}) | to_entries[]
              | select($pod[slot(.key)] != .value or $podAnnotations[slot(.key)] != .value)
              | "Job/\($job) pod \(slot(.key)) label=\($pod[slot(.key)] // "absent") annotation=\($podAnnotations[slot(.key)] // "absent") want=\(.value)" )
          , ( $instance | to_entries[]
              | select($podAnnotations[slot(.key)] != .value)
              | "Job/\($job) pod \(slot(.key)) annotation=\($podAnnotations[slot(.key)] // "absent") want=\(.value)" )
          , (($selectors - $ids)[] | "missing selector-bearing object \(.)")
          , ( $rendered[]
              | "\(.kind)/\(.metadata.name)" as $id
              | select($selectors | index($id))
              | ((.spec.selector.matchLabels // .spec.selector) // {}) as $selector
              | if ($selector | length) == 0 then "\($id) carries no selector, so it proves nothing about hook isolation"
                elif selects($pod; $selector) then "\($id) selector \($selector | tojson) selects the Job/\($job) pod"
                else empty end ) ] | .[]'
  }

  hook_is_isolated() {
    local description="$1"
    shift
    local offenders
    offenders="$(hook_offenders "$@")"
    if [ -n "${offenders}" ]; then
      echo "❌ ${description}" >&2
      printf '%s\n' "${offenders}" >&2
      exit 1
    fi
  }

  rejects_hook() {
    local description="$1"
    shift
    if [ -z "$(hook_offenders "$@")" ]; then
      echo "❌ ${description}: the hook-isolation assertion accepted the sabotage" >&2
      exit 1
    fi
  }

  helm template "${release}" chart --namespace "${namespace}" >"${tmp}/base.yaml"
  helm template "${release}" chart --namespace "${namespace}" --values chart/values.example.yaml >"${tmp}/example.yaml"
  helm template "${release}" chart --namespace "${namespace}" --values chart/values.example.yaml --values chart/values.lapras.yaml >"${tmp}/lapras.yaml"
  helm template "${release}" chart --namespace "${namespace}" --set global.labelPrefix=example.dev >"${tmp}/base-override.yaml"
  helm template "${release}" chart --namespace "${namespace}" --values chart/values.example.yaml --set global.labelPrefix=example.dev >"${tmp}/example-override.yaml"
  helm template "${release}" chart --namespace "${namespace}" --values chart/values.example.yaml --values chart/values.lapras.yaml --set global.labelPrefix=example.dev >"${tmp}/lapras-override.yaml"
  # A preview-enabled stack. Under preview both recorded halves are the
  # receipt-bound petname, and `global.instance` is the SINGLE value surface both
  # the wrapper's helpers and the pinned dependency's annotation templates resolve
  # through — so this render is what proves one release records one identity. The
  # gate previously rendered six stacks, none of them preview, which is how a
  # dependency that hard-coded the physical pair went unreported.
  helm template "${release}" chart --namespace "${namespace}" --values chart/values.example.yaml --set global.instance.preview.enabled=true >"${tmp}/preview.yaml"

  carries_projection "the base stack projection" "${tmp}/base.yaml" atomi.cloud '' "${base_objects}" "${base_projection}" "${physical_instance}"
  carries_projection "the example stack projection" "${tmp}/example.yaml" atomi.cloud '' "${example_objects}" "${example_projection}" "${physical_instance}"
  carries_projection "the example+lapras stack projection" "${tmp}/lapras.yaml" atomi.cloud '' "${lapras_objects}" "${lapras_projection}" "${physical_instance}"
  carries_projection "the preview stack projection and recorded preview identity" "${tmp}/preview.yaml" atomi.cloud '' "${example_objects}" "${example_projection}" "${preview_instance}"
  # The override runs re-assert the same per-object truth under the new prefix and
  # additionally require that no key under the default prefix survives, so an
  # override that merely adds keys cannot pass. `example.dev` is a different number
  # of dot-separated segments from `atomi.cloud`, so a prefix that was fused into a
  # rendered key by string surgery rather than carried whole is caught here too.
  carries_projection "the base stack prefix override" "${tmp}/base-override.yaml" example.dev atomi.cloud "${base_objects}" "${base_projection}" "${physical_instance}"
  carries_projection "the example stack prefix override" "${tmp}/example-override.yaml" example.dev atomi.cloud "${example_objects}" "${example_projection}" "${physical_instance}"
  carries_projection "the example+lapras stack prefix override" "${tmp}/lapras-override.yaml" example.dev atomi.cloud "${lapras_objects}" "${lapras_projection}" "${physical_instance}"

  # The hook pod keeps the whole service-tree projection and the recorded instance
  # pair, and still selects out of every primary Service and workload selector, in
  # every stack and under the prefix override.
  hook_is_isolated "the base stack hook pod identity" "${tmp}/base.yaml" atomi.cloud "${base_projection}" "${physical_instance}"
  hook_is_isolated "the example stack hook pod identity" "${tmp}/example.yaml" atomi.cloud "${example_projection}" "${physical_instance}"
  hook_is_isolated "the example+lapras stack hook pod identity" "${tmp}/lapras.yaml" atomi.cloud "${lapras_projection}" "${physical_instance}"
  hook_is_isolated "the preview stack hook pod identity" "${tmp}/preview.yaml" atomi.cloud "${example_projection}" "${preview_instance}"
  hook_is_isolated "the base stack hook pod identity under a prefix override" "${tmp}/base-override.yaml" example.dev "${base_projection}" "${physical_instance}"
  hook_is_isolated "the example+lapras stack hook pod identity under a prefix override" "${tmp}/lapras-override.yaml" example.dev "${lapras_projection}" "${physical_instance}"

  # Two sabotage controls, each run against a throwaway copy of the chart so the
  # working tree is never mutated. Each restores exactly the defect the assertion
  # above exists to catch; if the render still reads as clean, the assertion is
  # asserting nothing and this mode fails here rather than downstream.
  sabotage_chart() {
    rm -rf "${tmp}/sabotage"
    mkdir -p "${tmp}/sabotage"
    cp -R chart "${tmp}/sabotage/chart"
  }

  # Control A: give the hook pod the primary workload's selector identity back. The
  # rest of the projection is untouched, so only the selector comparison can catch
  # it — and it must.
  sabotage_chart
  sed -i 's#include "diene-helm-wrapper.hookLabels" (dict "root" . "token" "migration") | nindent 8#include "diene-helm-wrapper.labels" . | nindent 8#' "${tmp}/sabotage/chart/templates/migration-job.yaml"
  grep -qF 'diene-helm-wrapper.labels" . | nindent 8' "${tmp}/sabotage/chart/templates/migration-job.yaml" || {
    echo "❌ the hook-isolation sabotage did not apply; its control proves nothing" >&2
    exit 1
  }
  helm template "${release}" "${tmp}/sabotage/chart" --namespace "${namespace}" >"${tmp}/sabotaged-hook.yaml"
  rejects_hook "restoring the primary selector identity on the migration pod" \
    "${tmp}/sabotaged-hook.yaml" atomi.cloud "${base_projection}" "${physical_instance}"

  # Control B: hard-code the pinned dependency's instance annotations back to the
  # physical pair. Every physical-mode render stays byte-identical, exactly as the
  # defect did, so only the preview stack can catch it — and it must.
  sabotage_chart
  sed -i \
    -e "s#'{{ include \"diene-helm-wrapper.instanceOriginal\" . }}'#'${instance_original}'#" \
    -e "s#'{{ include \"diene-helm-wrapper.instanceSegment\" . }}'#'${instance_label}'#" \
    "${tmp}/sabotage/chart/values.yaml"
  if grep -qF 'diene-helm-wrapper.instanceOriginal' "${tmp}/sabotage/chart/values.yaml" ||
    ! grep -qF "/instance-original': '${instance_original}'" "${tmp}/sabotage/chart/values.yaml"; then
    echo "❌ the hard-coded upstream instance sabotage did not apply; its control proves nothing" >&2
    exit 1
  fi
  helm template "${release}" "${tmp}/sabotage/chart" --namespace "${namespace}" --values chart/values.example.yaml >"${tmp}/sabotaged-physical.yaml"
  carries_projection "the hard-coded upstream instance sabotage must stay invisible in physical mode, or the preview control below proves nothing else" \
    "${tmp}/sabotaged-physical.yaml" atomi.cloud '' "${example_objects}" "${example_projection}" "${physical_instance}"
  helm template "${release}" "${tmp}/sabotage/chart" --namespace "${namespace}" --values chart/values.example.yaml --set global.instance.preview.enabled=true >"${tmp}/sabotaged-preview.yaml"
  rejects_projection "hard-coded physical instance annotations on the pinned dependency under preview" \
    "${tmp}/sabotaged-preview.yaml" atomi.cloud '' "${example_objects}" "${example_projection}" "${preview_instance}"

  # A prefix that cannot be a Kubernetes label-key prefix is refused at BOTH
  # boundaries independently — once by the generated values schema before a
  # template runs, and once with --skip-schema-validation so the same bytes reach
  # the helper and its named reason is what refuses. The forward projection now
  # computes keys rather than spelling them out, so an unvalidated prefix would
  # render objects the API server rejects long after this chart claimed success.
  refuses_prefix_at_both_boundaries() {
    local label="$1" prefix="$2" schema_reason="$3" helper_reason="$4"
    refuses "${label}, at the values schema" "${schema_reason}" --set-string "global.labelPrefix=${prefix}"
    refuses "${label}, at the prefix helper" "${helper_reason}" --skip-schema-validation --set-string "global.labelPrefix=${prefix}"
  }

  refuses_prefix_at_both_boundaries "a leading-dash label prefix" -example.dev \
    "at '/global/labelPrefix': '-example.dev' does not match pattern" \
    'LabelPrefixInvalid: segment "-example" of label prefix "-example.dev"'
  refuses_prefix_at_both_boundaries "an empty label-prefix segment" example..dev \
    "at '/global/labelPrefix': 'example..dev' does not match pattern" \
    'LabelPrefixInvalid: segment 2 of label prefix "example..dev" is empty'
  refuses_prefix_at_both_boundaries "an uppercase label prefix" Example.dev \
    "at '/global/labelPrefix': 'Example.dev' does not match pattern" \
    'LabelPrefixInvalid: segment "Example" of label prefix "Example.dev"'
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
  # Every declared dependency module names exactly one engine, keyed by its own type.
  # `all` over an empty list is TRUE, so the assertion demanded a PlatformDependency
  # and a non-empty flattened module map before it ever compared a key: without them
  # a render that dropped the CR entirely, or emitted it with no modules, passed this
  # gate while proving nothing. The two controls below are what keep that honest.
  engines_match_declared_types() {
    yq eval-all -o=json '.' "$1" | jq -s -e '
      map(select(.kind == "PlatformDependency")) as $dependencies
      | ($dependencies | length) == 1
        and ( ( $dependencies[0].spec
                | [.database, .kv, .cache, .store] | map(. // {}) | add | to_entries ) as $modules
              | ($modules | length) > 0
                and ($modules | all(.value.engine != null and ((.value.engine | keys) == [.value.type]))) )' >/dev/null
  }

  engines_match_declared_types "${tmp}/primordial.yaml" || {
    echo "❌ a declared dependency module does not name exactly one engine keyed by its own type" >&2
    exit 1
  }

  # Control A: the same assertion must redden on a module whose engine key no longer
  # equals its declared type, or it is asserting nothing about the pairing.
  helm template "${release}" chart --namespace "${namespace}" --values chart/values.example.yaml --set primordial.enabled=true \
    --set-string primordial.platformDependency.modules.database.maindb.type=pgvector >"${tmp}/mismatched-engine.yaml"
  if engines_match_declared_types "${tmp}/mismatched-engine.yaml"; then
    echo "❌ the engine/type assertion accepted a module whose engine key is not its declared type" >&2
    exit 1
  fi

  # Control B: and it must redden when no PlatformDependency is rendered at all,
  # which is exactly the vacuous pass the empty-list `all` used to hand out.
  helm template "${release}" chart --namespace "${namespace}" --values chart/values.example.yaml --set primordial.enabled=false >"${tmp}/no-dependency.yaml"
  if engines_match_declared_types "${tmp}/no-dependency.yaml"; then
    echo "❌ the engine/type assertion passed with no PlatformDependency rendered" >&2
    exit 1
  fi

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
  instance_hostname="$(yq -r "${contracts} | .data.\"instance.hostname\"" "${tmp}/lpsm.yaml")"
  expected_original="$(yq -r '.global.instance.original' chart/values.yaml)"
  expected_label="$(yq -r '.global.instance.label' chart/values.yaml)"
  [ "${ordinary}" != "api.wrapper.sample.example.cluster.atomi.cloud" ] && echo "❌ ordinary LPSM hostname mismatch" >&2 && exit 1
  [ "${instance}" != "api.wrapper.sample.run001.example.local.example.invalid" ] && echo "❌ instance LPSM hostname mismatch" >&2 && exit 1
  jq -e '.landscape == "example" and .platform == "sample" and .service == "wrapper" and .module == "api" and .instance == "run001"' <<<"${parsed}" >/dev/null
  # The committed original is repository-qualified and longer than one DNS label, so
  # this is the round trip the old one-label input could not express: both exact
  # values come back out, and the hostname segment is the minted label alone.
  [ "${#expected_original}" -le 63 ] && echo "❌ the committed physical original is short enough to be its own DNS label, so the round trip proves nothing" >&2 && exit 1
  [ "${original}" != "${expected_original}" ] && echo "❌ recorded instance original does not equal the supplied repository-qualified id" >&2 && exit 1
  [ "${label}" != "${expected_label}" ] && echo "❌ recorded instance label does not equal the authorized minter's label" >&2 && exit 1
  [ "${instance_hostname}" != "api.wrapper.sample.${expected_label}.example.local.example.invalid" ] && echo "❌ the instance hostname segment is not the minted label" >&2 && exit 1

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

  # One contract key of one extra render, compared exactly.
  accepts_contract_key() {
    local description="$1" key="$2" expected="$3"
    shift 3
    local got
    helm template "${release}" chart --namespace "${namespace}" --values chart/values.example.yaml "$@" >"${tmp}/accepted-key.yaml"
    got="$(yq -r "${contracts} | .data.\"${key}\"" "${tmp}/accepted-key.yaml")"
    if [ "${got}" != "${expected}" ]; then
      echo "❌ ${description}: expected '${expected}', got '${got}'" >&2
      exit 1
    fi
  }

  # The ordinary four-slot form parses back with the instance returned separately and
  # EMPTY, so the optional projection is genuinely optional in both directions. The
  # optional-instance parse above is the other arity of the same boundary.
  accepts_contract_key "the ordinary four-slot parse" lpsm.parsed \
    '{"instance":"","landscape":"example","module":"api","platform":"sample","service":"wrapper"}' \
    --set-string contracts.lpsm.parseHostname=api.wrapper.sample.example.local.example.invalid

  # A second pre-minted pair, supplied rather than committed: a genuinely long
  # repository-qualified original and a short stable hash label. Both halves round
  # trip byte-for-byte and the hostname carries the label, never the original.
  long_original=github.com/AtomiCloud/diene.all/charts/helm-wrapper/pull-requests/12345/attempt-7
  hash_label=wrapper-pr12345-7q2m9x
  minted_pair=(--set-string "global.instance.original=${long_original}" --set-string "global.instance.label=${hash_label}")
  accepts_contract_key "a long repository-qualified original" instance.original "${long_original}" "${minted_pair[@]}"
  accepts_contract_key "the minted label recorded beside it" instance.label "${hash_label}" "${minted_pair[@]}"
  accepts_contract_key "the hostname segment taken from the minted label" instance.hostname \
    "api.wrapper.sample.${hash_label}.example.local.example.invalid" "${minted_pair[@]}"

  helm template "${release}" chart --namespace "${namespace}" --values chart/values.example.yaml \
    --set global.instance.preview.enabled=true --set-string "contracts.lpsm.instanceZone=${zone}" >"${tmp}/preview.yaml"
  preview_host="$(yq -r "${contracts} | .data.\"preview.hostname\"" "${tmp}/preview.yaml")"
  [ "${preview_host}" != "api.wrapper.sample.${petname}.castform.${zone}" ] && echo "❌ preview coordinate mismatch" >&2 && exit 1

  helm template "${release}" chart --namespace "${namespace}" --values chart/values.example.yaml \
    --set global.instance.preview.enabled=true --set-string "contracts.lpsm.instanceZone=${zone}" \
    --set-string "global.instance.preview.canonical.previewPetname=${petname}-ekj" \
    --set-string "global.instance.preview.receipt.previewPetname=${petname}-ekj" \
    --set-string "global.instance.preview.receipt.collision.liveFullLeaseDigest=${other}" >"${tmp}/collision.yaml"
  collision_host="$(yq -r "${contracts} | .data.\"preview.hostname\"" "${tmp}/collision.yaml")"
  [ "${collision_host}" != "api.wrapper.sample.${petname}-ekj.castform.${zone}" ] && echo "❌ live-collision petname mismatch" >&2 && exit 1

  refuses "an unverified canonical digest" "PreviewIdentityMismatch: canonical full digest" --set global.instance.preview.enabled=true --set-string "global.instance.preview.canonical.fullLeaseDigest=${other}"
  refuses "a caller-supplied collision suffix" "PreviewIdentityMismatch: collision suffix" --set global.instance.preview.enabled=true --set-string "global.instance.preview.canonical.previewPetname=${petname}-abc" --set-string "global.instance.preview.receipt.previewPetname=${petname}-abc" --set-string "global.instance.preview.receipt.collision.liveFullLeaseDigest=${other}"
  refuses "a same-digest collision" "same full digest is an idempotent join" --set global.instance.preview.enabled=true --set-string "global.instance.preview.canonical.previewPetname=${petname}-ekj" --set-string "global.instance.preview.receipt.previewPetname=${petname}-ekj" --set-string "global.instance.preview.receipt.collision.liveFullLeaseDigest=${digest}"
  refuses "an unresolved branch pin" "neither a released version nor a full commit" --set global.instance.preview.enabled=true --set-string 'global.instance.preview.manifest.pins.nitroso\.zinc=main'
  refuses "a dash-fused Garden hostname" "must use the canonical dotted LPSM form" --set-string contracts.lpsm.parseHostname=api-wrapper-sample-run001-example.local.example.invalid
  refuses "an uppercase parser input" "must be a lowercase DNS-1123 label" --set-string contracts.lpsm.parseHostname=API.wrapper.sample.run001.example.local.example.invalid

  # The forward derivation once accepted labels its own inverse parser rejects, so
  # every vector below is asserted at BOTH boundaries independently: once as the
  # generated values schema refusing the malformed value before a template runs,
  # and once with --skip-schema-validation so the same bytes reach the helper and
  # its named reason is what refuses. Asserting only the pair's outer half would
  # let the helper go slack again behind the schema, which is exactly how the
  # defect survived.
  #
  # `parseHostname` is pinned to a VALID, independent hostname in every label
  # vector. Left to default it is derived from the very slot under test, so the
  # inverse parser would refuse the derived garbage and the vector would pass
  # while proving nothing about the forward derivation. The zone vectors move
  # `ordinaryZone`, which no parser ever reads, for the same reason.
  valid_parse=api.wrapper.sample.run001.example.local.example.invalid
  overlong_label="$(printf 'a%.0s' {1..64})"

  refuses_at_both_boundaries() {
    local label="$1" schema_reason="$2" helper_reason="$3"
    shift 3
    refuses "${label}, at the values schema" "${schema_reason}" "$@"
    refuses "${label}, at the hostname helper" "${helper_reason}" --skip-schema-validation "$@"
  }

  refuses_at_both_boundaries "a leading-dash landscape label" \
    "at '/contracts/lpsm/landscape': '-example' does not match pattern" \
    'HostnameLabelInvalid: landscape label "-example" must start with a lowercase alphanumeric byte' \
    --set-string contracts.lpsm.landscape=-example --set-string "contracts.lpsm.parseHostname=${valid_parse}"

  refuses_at_both_boundaries "a leading-dash service label" \
    "at '/contracts/lpsm/service': '-wrapper' does not match pattern" \
    'HostnameLabelInvalid: service label "-wrapper" must start with a lowercase alphanumeric byte' \
    --set-string contracts.lpsm.service=-wrapper --set-string "contracts.lpsm.parseHostname=${valid_parse}"

  refuses_at_both_boundaries "a trailing-dash module label" \
    "at '/contracts/lpsm/module': 'api-' does not match pattern" \
    'HostnameLabelInvalid: module label "api-" must end with a lowercase alphanumeric byte' \
    --set-string contracts.lpsm.module=api- --set-string "contracts.lpsm.parseHostname=${valid_parse}"

  refuses_at_both_boundaries "a trailing-dash optional-instance label" \
    "at '/contracts/lpsm/instance': 'run001-' does not match pattern" \
    'HostnameLabelInvalid: instance label "run001-" must end with a lowercase alphanumeric byte' \
    --set-string contracts.lpsm.instance=run001- --set-string "contracts.lpsm.parseHostname=${valid_parse}"

  refuses_at_both_boundaries "a 64-byte landscape label" \
    "at '/contracts/lpsm/landscape': maxLength: got 64, want 63" \
    "HostnameLabelInvalid: landscape label \"${overlong_label}\" is 64 bytes" \
    --set-string "contracts.lpsm.landscape=${overlong_label}" --set-string "contracts.lpsm.parseHostname=${valid_parse}"

  refuses_at_both_boundaries "a trailing-dash zone segment" \
    "at '/contracts/lpsm/ordinaryZone': 'bad-.atomi.cloud' does not match pattern" \
    'HostnameLabelInvalid: zone label 1 of "bad-.atomi.cloud" "bad-" must end with a lowercase alphanumeric byte' \
    --set-string contracts.lpsm.ordinaryZone=bad-.atomi.cloud

  refuses_at_both_boundaries "an empty zone segment" \
    "at '/contracts/lpsm/ordinaryZone': 'cluster..atomi.cloud' does not match pattern" \
    'HostnameLabelInvalid: zone label 2 of "cluster..atomi.cloud" is empty' \
    --set-string contracts.lpsm.ordinaryZone=cluster..atomi.cloud

  refuses_at_both_boundaries "a leading-dot zone" \
    "at '/contracts/lpsm/ordinaryZone': '.atomi.cloud' does not match pattern" \
    'HostnameLabelInvalid: zone label 1 of ".atomi.cloud" is empty' \
    --set-string contracts.lpsm.ordinaryZone=.atomi.cloud

  refuses_at_both_boundaries "an uppercase zone segment" \
    "at '/contracts/lpsm/ordinaryZone': 'cluster.Atomi.cloud' does not match pattern" \
    'HostnameLabelInvalid: zone label 2 of "cluster.Atomi.cloud" "Atomi" must start with a lowercase alphanumeric byte' \
    --set-string contracts.lpsm.ordinaryZone=cluster.Atomi.cloud

  refuses_at_both_boundaries "an inner-uppercase zone segment" \
    "at '/contracts/lpsm/ordinaryZone': 'cluster.atOmi.cloud' does not match pattern" \
    'HostnameLabelInvalid: zone label 2 of "cluster.atOmi.cloud" "atOmi" may hold only lowercase alphanumerics and internal dashes' \
    --set-string contracts.lpsm.ordinaryZone=cluster.atOmi.cloud

  # The preview receipt gets the same two-boundary treatment for the same reason.
  # Each of these four used to be asserted with an OR of a schema reason and a helper
  # reason, so the schema alone satisfied the vector and the preview helper could have
  # stopped refusing without anything reddening.
  preview=(--set global.instance.preview.enabled=true)

  refuses_at_both_boundaries "an unversioned petname word list" \
    "at '/global/instance/preview/receipt/wordList': 'diene.preview-wordlist' does not match pattern" \
    'PreviewIdentityUnavailable: petname word list "diene.preview-wordlist" is not a versioned diene.preview-wordlist' \
    "${preview[@]}" --set-string global.instance.preview.receipt.wordList=diene.preview-wordlist

  refuses_at_both_boundaries "a petname outside the NOUN-VERB-NOUN grammar" \
    "at '/global/instance/preview/canonical/previewPetname': 'otterbeatspotato' does not match pattern" \
    'PreviewIdentityUnavailable: "otterbeatspotato" is not a versioned NOUN-VERB-NOUN petname' \
    "${preview[@]}" --set-string global.instance.preview.canonical.previewPetname=otterbeatspotato \
    --set-string global.instance.preview.receipt.previewPetname=otterbeatspotato

  refuses_at_both_boundaries "a collision suffix longer than three characters" \
    "at '/global/instance/preview/canonical/previewPetname': '${petname}-ekj9' does not match pattern" \
    "PreviewIdentityUnavailable: \"${petname}-ekj9\" is not a versioned NOUN-VERB-NOUN petname" \
    "${preview[@]}" --set-string "global.instance.preview.canonical.previewPetname=${petname}-ekj9" \
    --set-string "global.instance.preview.receipt.previewPetname=${petname}-ekj9" \
    --set-string "global.instance.preview.receipt.collision.liveFullLeaseDigest=${other}"

  refuses_at_both_boundaries "a fork source outside the ruled pair" \
    "at '/global/instance/preview/receipt/forkSource': value must be one of 'staging', 'production'" \
    'PreviewIdentityUnavailable: forkSource "serving" is neither staging nor production' \
    "${preview[@]}" --set-string global.instance.preview.receipt.forkSource=serving

  # The physical instance pair. A long or repository-qualified original is ACCEPTED
  # above — the refusals that used to reject exactly that were false, because this
  # chart records the minter's pair rather than re-deriving it. What is refused is a
  # malformed half, and a half with no partner.
  overlong_original="github.com/atomicloud/$(printf 'a%.0s' {1..232})"

  refuses_at_both_boundaries "an uppercase minted instance label" \
    "at '/global/instance/label': 'PR-12345' does not match pattern" \
    'HostnameLabelInvalid: global.instance.label "PR-12345" must start with a lowercase alphanumeric byte' \
    --set-string global.instance.label=PR-12345

  refuses_at_both_boundaries "a 64-byte minted instance label" \
    "at '/global/instance/label': maxLength: got 64, want 63" \
    "HostnameLabelInvalid: global.instance.label \"${overlong_label}\" is 64 bytes" \
    --set-string "global.instance.label=${overlong_label}"

  refuses_at_both_boundaries "a whitespace-bearing physical original" \
    "at '/global/instance/original': 'repository a/pr-123' does not match pattern" \
    'InstanceOriginalInvalid: global.instance.original "repository a/pr-123" must start and end with an alphanumeric' \
    --set-string 'global.instance.original=repository a/pr-123'

  refuses_at_both_boundaries "a 254-byte physical original" \
    "at '/global/instance/original': maxLength: got 254, want 253" \
    'InstanceOriginalInvalid: global.instance.original is 254 bytes' \
    --set-string "global.instance.original=${overlong_original}"

  # Removing a half outright is caught by the generated schema's own `required` list;
  # emptying one reaches the helper, which is the only boundary that can see one half
  # standing without the other.
  refuses_at_both_boundaries "an instance label removed from the pair" \
    "at '/global/instance': missing property 'label'" \
    'InstancePairIncomplete: global.instance.original' \
    --set global.instance.label=null

  refuses_at_both_boundaries "an instance original removed from the pair" \
    "at '/global/instance': missing property 'original'" \
    'InstancePairIncomplete: global.instance.label' \
    --set global.instance.original=null

  refuses "an original orphaned by an emptied label" 'InstancePairIncomplete: global.instance.original' --set-string global.instance.label=
  refuses "a label orphaned by an emptied original" 'InstancePairIncomplete: global.instance.label' --set-string global.instance.original=
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
  # A shim ahead of the real binary on PATH. It forwards every helm invocation
  # the packaging path needs and intercepts only the two that would reach a
  # registry, recording each attempt and refusing it. That turns "no external
  # publish happened" into an assertion about what was attempted rather than
  # trust in the dry-run flag, and it holds even if a future edit drops the flag.
  attempts="${tmp}/registry-attempts.log"
  stub_dir="${tmp}/stub"
  real_helm="$(command -v helm)"
  mkdir -p "${stub_dir}"
  cat >"${stub_dir}/helm" <<EOF
#!/usr/bin/env bash
case "\$1 \${2:-}" in
"push "* | "registry login")
  printf '%s\n' "helm \$*" >>"${attempts}"
  echo "❌ the publish stub intercepted a real registry call" >&2
  exit 97
  ;;
esac
exec "${real_helm}" "\$@"
EOF
  chmod +x "${stub_dir}/helm"
  : >"${attempts}"

  # Run publish.sh under the shim with the given environment, and report the
  # script's own exit status rather than the status of whatever ran last.
  # PUBLISH_MODE is unset on EVERY call before the caller's own assignments land,
  # so a default-mode assertion always tests the script's default rather than an
  # exported caller environment, and an explicit-mode assertion tests exactly the
  # mode it names. The unset lives here rather than at the call sites because
  # `env` rejects `-u` once a NAME=VALUE argument has been seen.
  publishes() {
    local status=0
    (
      unset PUBLISH_MODE
      export PATH="${stub_dir}:${PATH}"
      env "$@" bash ./scripts/ci/publish.sh
    ) 2>&1 || status=$?
    return "${status}"
  }

  # Omitting PUBLISH_MODE must select OCI. The completion line names the mode, the
  # OCI-only ref file is written, and the git-only repository index is NOT — so a
  # default that silently fell back to git cannot read as a pass.
  if ! default_out="$(publishes OCI_REGISTRY=ghcr.io OCI_REPOSITORY=atomicloud/diene.all PUBLISH_DRY_RUN=true RELEASE_VERSION=v0.1.0 PUBLISH_OUTPUT_DIR="${tmp}/default")"; then
    echo "❌ publishing with PUBLISH_MODE omitted failed" >&2
    printf '%s\n' "${default_out}" >&2
    exit 1
  fi
  grep -qF '✅ oci chart publish dry-run complete for 0.1.0' <<<"${default_out}" || {
    echo "❌ an omitted PUBLISH_MODE did not select OCI" >&2
    printf '%s\n' "${default_out}" >&2
    exit 1
  }
  [ ! -s "${tmp}/default/diene-helm-wrapper-0.1.0.tgz" ] && echo "❌ default-mode chart package missing" >&2 && exit 1
  rg -q '^oci://ghcr.io/atomicloud/diene.all$' "${tmp}/default/oci-ref.txt"
  [ -e "${tmp}/default/index.yaml" ] && echo "❌ an omitted PUBLISH_MODE wrote a git chart-repository index" >&2 && exit 1
  [ -s "${attempts}" ] && echo "❌ the default OCI dry run attempted a real registry call" >&2 && cat "${attempts}" >&2 && exit 1

  # The control for the two assertions above: with the dry run switched off, the
  # very same PATH must reach `helm push`, and the shim must record and refuse it.
  # Without this, an unloaded shim and a clean run look identical — an empty log
  # would prove nothing at all. The registry is the reserved `.invalid` TLD, which
  # by RFC 6761 never resolves, so even the failure mode this control exists to
  # catch — a shim that stopped intercepting — cannot reach a real registry.
  if publishes OCI_REGISTRY=registry.invalid OCI_REPOSITORY=atomicloud/diene.all PUBLISH_DRY_RUN=false RELEASE_VERSION=v0.1.0 PUBLISH_OUTPUT_DIR="${tmp}/intercepted" >/dev/null; then
    echo "❌ a non-dry-run publish succeeded without reaching the intercepting stub" >&2
    exit 1
  fi
  grep -qE '^helm push .*oci://registry\.invalid/atomicloud/diene\.all$' "${attempts}" || {
    echo "❌ the stub never saw the default mode's push, so its silence proves nothing" >&2
    cat "${attempts}" >&2
    exit 1
  }
  : >"${attempts}"

  # Explicit modes still win over the default, in both directions.
  OCI_REGISTRY=ghcr.io OCI_REPOSITORY=atomicloud/diene.all PUBLISH_MODE=oci PUBLISH_DRY_RUN=true RELEASE_VERSION=v0.1.0 PUBLISH_OUTPUT_DIR="${tmp}/oci" bash ./scripts/ci/publish.sh >/dev/null
  [ ! -s "${tmp}/oci/diene-helm-wrapper-0.1.0.tgz" ] && echo "❌ OCI chart package missing" >&2 && exit 1
  rg -q '^oci://ghcr.io/atomicloud/diene.all$' "${tmp}/oci/oci-ref.txt"
  if ! git_out="$(publishes PUBLISH_MODE=git PUBLISH_DRY_RUN=true RELEASE_VERSION=v0.1.0 PUBLISH_OUTPUT_DIR="${tmp}/explicit-git")"; then
    echo "❌ the explicit git mode failed" >&2
    printf '%s\n' "${git_out}" >&2
    exit 1
  fi
  grep -qF '✅ git chart publish dry-run complete for 0.1.0' <<<"${git_out}" || {
    echo "❌ an explicit PUBLISH_MODE=git was overridden by the OCI default" >&2
    printf '%s\n' "${git_out}" >&2
    exit 1
  }
  [ ! -s "${tmp}/explicit-git/index.yaml" ] && echo "❌ the explicit git mode wrote no chart-repository index" >&2 && exit 1
  [ -e "${tmp}/explicit-git/oci-ref.txt" ] && echo "❌ the explicit git mode wrote an OCI ref" >&2 && exit 1

  if output="$(publishes PUBLISH_MODE=svn PUBLISH_DRY_RUN=true RELEASE_VERSION=v0.1.0 PUBLISH_OUTPUT_DIR="${tmp}/unknown")"; then
    echo "❌ an unknown PUBLISH_MODE was accepted" >&2
    exit 1
  fi
  grep -qF 'PUBLISH_MODE must be git or oci' <<<"${output}"

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
