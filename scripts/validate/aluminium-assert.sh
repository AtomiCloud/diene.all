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
