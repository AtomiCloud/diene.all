#!/usr/bin/env bash
# ### aluminium-contract-assertions
# #### source: aluminium
# Shared semantic assertions used by both production inputs and mutated
# negative fixtures.
set -euo pipefail

mode="${1:-}"
subject="${2:-}"
expected_prefix="${3:-}"

[ -z "${mode}" ] && echo "❌ assertion mode not set" >&2 && exit 1
[ -z "${subject}" ] && echo "❌ assertion subject not set" >&2 && exit 1

case "${mode}" in
features-off)
  yq eval-all -o=json '.' "${subject}" |
    jq -s -e '
      def forbidden_resource_name:
        test("(^|-)(beyla|opencost)(-|$)"; "i");
      def config_text:
        [.[] | select(.kind == "ConfigMap") | (.data // {}) | .. | strings] | join("\n");
      ([.[] |
          ((.metadata.name? // empty),
           (.spec.template.spec.containers[]?.image? // empty))] |
        all(.[]; forbidden_resource_name | not)) and
      (config_text as $config |
        ($config | test("// Feature: Application Observability")) and
        ($config | test("// Feature: Cluster Metrics")) and
        ($config | test("// Feature: Pod Logs \\(OpenTelemetry\\)")) and
        ($config |
          test("// Self Reporting|kubernetes_monitoring_telemetry|grafana_kubernetes_monitoring_build_info|// Feature: Cluster Events|declare \"cluster_events\"|// Feature: Cost Metrics|declare \"cost_metrics\"|// Feature: Profiling|declare \"profiling\""; "i") |
          not))
    ' >/dev/null
  ;;

gigapipe-naming)
  if rg -ni --glob '!charts/**' 'qryn' \
    "${subject}/chart" \
    "${subject}/Taskfile.yaml" \
    "${subject}/scripts/local" \
    "${subject}/scripts/ci" \
    "${subject}/.github"; then
    echo "❌ legacy destination reference found in chart product input" >&2
    exit 1
  fi
  yq eval -o=json '.' "${subject}/chart/values.yaml" |
    jq -e '
      (.upstream.destinations | has("gigapipe")) and
      (.upstream.destinations.gigapipe.type == "otlp") and
      (.upstream.destinations.gigapipe.logs.enabled == true) and
      (.upstream.destinations.gigapipe.traces.enabled == true)
    ' >/dev/null
  ;;

literal-secrets)
  yq eval-all -o=json '.' "${subject}"/values*.yaml |
    jq -s -e '
      [ .[] | .. | objects | to_entries[] |
        select(.key | test("^(password|passphrase|token|api[_-]?key|client[_-]?secret|secret[_-]?key|access[_-]?key|private[_-]?key|credential)$"; "i")) |
        select(.value != null and .value != "" and .value != false and .value != {} and .value != [])
      ] | length == 0
    ' >/dev/null
  ;;

otlp-surface)
  yq eval-all -o=json '.' "${subject}"/values*.yaml |
    jq -s -e '
      reduce .[] as $values ({}; . * $values) |
      .upstream.destinations as $destinations |
      (($destinations | keys | sort) == ["gigapipe", "victoriametrics"]) and
      ($destinations | to_entries |
        all(.[];
          .value.type == "otlp" and
          .value.protocol == "http" and
          ((.value.metrics | keys) == ["enabled"]) and
          ((.value.logs | keys) == ["enabled"]) and
          ((.value.traces | keys) == ["enabled"]))) and
      ([paths(scalars) as $path |
          select($path[0] == "upstream" and
                 $path[1] == "destinations" and
                 $path[-1] == "protocol") |
          $path] |
        all(.[]; length == 4))
    ' >/dev/null
  ;;

k3d-create-log)
  [ -z "${expected_prefix}" ] && echo "❌ expected invocation-local kubeconfig path not set" >&2 && exit 1
  awk -F '\t' -v kubeconfig="${expected_prefix}" '
    {
      if ($1 != "kubeconfig=" kubeconfig) {
        invalid = 1
      }
      if ($2 ~ /^cluster create /) {
        creates++
        update_default = index($2, "--kubeconfig-update-default=false") > 0
        switch_context = index($2, "--kubeconfig-switch-context=false") > 0
      }
    }
    END {
      exit !(NR == 3 && !invalid && creates == 1 && update_default && switch_context)
    }
  ' "${subject}"
  ;;

k3d-proof-script)
  rg -Fqx 'umask 077' "${subject}" >/dev/null
  rg -Fq 'kubeconfig="${artifact_dir}/kubeconfig.yaml"' "${subject}"
  rg -Fq 'export KUBECONFIG="${kubeconfig}"' "${subject}"
  rg -Fq 'k3d kubeconfig get "${cluster_name}" >"${kubeconfig_tmp}"' "${subject}"
  rg -Fq 'chmod 600 "${kubeconfig}"' "${subject}"
  rg -Fq 'kubectl_args=(--kubeconfig "${kubeconfig}" --context "${kube_context}" --namespace "${namespace}")' "${subject}"
  rg -Fq '  KUBECONFIG="${kubeconfig}"' "${subject}"
  awk '
    index($0, "export KUBECONFIG=\"${kubeconfig}\"") > 0 {
      export_line = NR
    }
    !first_k3d && $0 ~ /(^|[[:space:]])k3d (cluster|registry|kubeconfig) / {
      first_k3d = NR
    }
    END {
      exit !(export_line > 0 && first_k3d > export_line)
    }
  ' "${subject}"
  awk '
    /^[[:space:]]*kubectl / {
      calls++
      if (index($0, "kubectl \"${kubectl_args[@]}\"") == 0) {
        unsafe++
      }
    }
    END {
      exit !(calls > 0 && unsafe == 0)
    }
  ' "${subject}"
  awk '
    /^helm upgrade --install aluminium chart/ {
      upgrades++
      block = 1
    }
    block && index($0, "--kubeconfig \"${kubeconfig}\"") > 0 {
      local_kubeconfig = 1
    }
    block && /helm-install[.]log/ {
      block = 0
    }
    END {
      exit !(upgrades == 1 && local_kubeconfig)
    }
  ' "${subject}"
  ;;

# The serialized k3d proof must register a helm repository for EVERY URL the
# chart declares as a dependency before invoking `helm dependency build`.
# Without that registration helm fails "no repository definition for <url>"
# (RB-266). Host-safe static check: no network, k3d, or provider action.
helm-repo-resolution)
  chart_yaml="${expected_prefix:-chart/Chart.yaml}"
  [ -f "${chart_yaml}" ] || {
    echo "❌ chart yaml not found: ${chart_yaml}" >&2
    exit 1
  }
  mapfile -t dep_repos < <(yq e '.dependencies[].repository' "${chart_yaml}")
  [ "${#dep_repos[@]}" -gt 0 ] || {
    echo "❌ chart declares no dependency repositories" >&2
    exit 1
  }
  for url in "${dep_repos[@]}"; do
    # A `helm repo add` line must register this exact dependency URL.
    rg -N 'helm repo add' "${subject}" | rg -Fq "${url}" ||
      {
        echo "❌ dependency repository ${url} is not registered via 'helm repo add'" >&2
        exit 1
      }
  done
  # The registration must precede `helm dependency build chart`.
  awk '
    /helm repo add[[:space:]]/ && !repo_add { repo_add = NR }
    /helm dependency build[[:space:]]+chart/ && !dep_build { dep_build = NR }
    END {
      exit !(repo_add > 0 && dep_build > 0 && repo_add < dep_build)
    }
  ' "${subject}" ||
    {
      echo "❌ helm repo registration does not precede helm dependency build" >&2
      exit 1
    }
  ;;

# RB-ALU-OTLP: the DESIGNED clustered receiver topology renders TWO Services
# that both expose otlp-http:4318 -- the primary receiver
# `aluminium-alloy-metrics` (routable ClusterIP) and the headless clustering
# Service `aluminium-alloy-metrics-cluster` (clusterIP: None). Counting every
# Service exposing 4318 is therefore ambiguous. This assertion selects the
# PRIMARY receiver by its exact stable name, asserts its OTLP/HTTP port and
# usable/readiness endpoint semantics (targetPort + populated selector), and
# tolerates the second Service while positively asserting it IS headless with
# its designed receiver-port topology. Subject: `kubectl get service -o json`.
otlp-primary-receiver)
  jq -e '
    (.items // []) as $svcs |
    [ $svcs[] |
      select(.metadata.name == "aluminium-alloy-metrics" and
        (.spec.clusterIP // "None") != "None" and
        any(.spec.ports[]?; .name == "otlp-http" and .port == 4318)) ] as $primary |
    [ $svcs[] |
      select(.metadata.name == "aluminium-alloy-metrics-cluster") ] as $cluster |
    ($primary | length) == 1 and
    ($cluster | length) == 1 and
    ($primary[0].spec.ports
      | map(select(.name == "otlp-http"))
      | (length == 1) and (.[0].port == 4318) and (.[0].targetPort != null)) and
    (($primary[0].spec.selector // {}) | length > 0) and
    ($cluster[0].spec.clusterIP == "None") and
    (any($cluster[0].spec.ports[]?; .name == "otlp-http" and .port == 4318))
  ' "${subject}" >/dev/null
  ;;

lpsm-labels)
  [ -z "${expected_prefix}" ] && echo "❌ expected label prefix not set" >&2 && exit 1
  yq eval-all -o=json '.' "${subject}" |
    jq -s -e --arg prefix "${expected_prefix}" '
      {
        ($prefix + "/platform"): "telemetry",
        ($prefix + "/service"): "aluminium",
        ($prefix + "/module"): "telemetry",
        ($prefix + "/layer"): "1"
      } as $expected |
      [.[] | select(.kind == "Alloy")] as $alloys |
      [.[] | select(.kind == "ExternalSecret")] as $secrets |
      ($alloys | length == 2) and
      ($alloys | all(.[]; .spec.alloy.labels == $expected)) and
      ($secrets | length == 1) and
      ($secrets | all(.[];
        .metadata.labels as $labels |
        ($expected | to_entries | all(.[]; $labels[.key] == .value)) and
        ([$labels | keys[] | select(test("/(platform|service|module|layer)$"))] |
          all(.[]; startswith($prefix + "/")))))
    ' >/dev/null
  ;;

*)
  echo "❌ unknown assertion mode '${mode}'" >&2
  exit 1
  ;;
esac

echo "✅ aluminium ${mode} assertion passed"
