#!/usr/bin/env bash
set -euo pipefail

app_manifest="${1:-}"
primordial_manifest="${2:-}"
expected_namespace="${3:-}"
expected_platform="${4:-}"
expected_dependencies="${5:-1}"

[ -s "${app_manifest}" ] || {
  echo "❌ app manifest is required" >&2
  exit 1
}
[ -s "${primordial_manifest}" ] || {
  echo "❌ primordial manifest is required" >&2
  exit 1
}
[ -n "${expected_namespace}" ] || {
  echo "❌ expected namespace is required" >&2
  exit 1
}
[ -n "${expected_platform}" ] || {
  echo "❌ expected platform is required" >&2
  exit 1
}

app_json="$(yq eval-all -o=json '.' "${app_manifest}" | jq -s 'map(select(. != null))')"
primordial_json="$(yq eval-all -o=json '.' "${primordial_manifest}" | jq -s 'map(select(. != null))')"

jq -e --arg namespace "${expected_namespace}" --arg platform "${expected_platform}" '
  (map(select(.kind == "Namespace")) | length == 1) and
  (map(select(.kind == "ExternalSecret")) | length == 1) and
  (map(select(.kind == "SecretStore")) | length == 1) and
  (map(select(.kind == "Namespace"))[0] as $ns |
    $ns.metadata.name == $namespace and
    ($ns.metadata.labels | keys | all(.[]; startswith("pod-security.kubernetes.io/") | not))) and
  (map(select(.kind == "ExternalSecret"))[0] as $es |
    $es.metadata.namespace == $namespace and
    $es.spec.secretStoreRef == {"kind":"ClusterSecretStore","name":"cobalt-sos"} and
    ($es.spec | has("data") | not) and
    ($es.spec.dataFrom | length >= 1) and
    all($es.spec.dataFrom[]; .extract.key | startswith("/"))) and
  (map(select(.kind == "SecretStore"))[0] as $store |
    $store.metadata.namespace == $namespace and
    $store.spec.provider.infisical.secretsScope.projectSlug == $platform and
    $store.spec.provider.infisical.auth.universalAuthCredentials.clientId.name == "carbon-token" and
    $store.spec.provider.infisical.auth.universalAuthCredentials.clientSecret.name == "carbon-token") and
  all(.[]; .metadata.labels["atomi.cloud/platform"] == $platform and .metadata.labels["atomi.cloud/service"] == "carbon") and
  (map(select(.kind == "PushSecret" or .kind == "Application" or .kind == "ApplicationSet")) | length == 0)
' <<<"${app_json}" >/dev/null || {
  echo "❌ app chart render violates the namespace/SoS/SecretStore contract" >&2
  exit 1
}

jq -e --arg platform "${expected_platform}" --argjson expected "${expected_dependencies}" '
  map(select(.kind == "PlatformDependency")) as $deps |
  ($deps | length == $expected) and
  ($deps | map([.spec.platform, .spec.landscape] | join("/")) | unique | length == $expected) and
  all($deps[];
    .apiVersion == "fleet.atomi.cloud/v1alpha1" and
    .spec.platform == $platform and
    (.spec.landscape | length > 0) and
    (.spec.placement.preferredHost | length > 0) and
    .metadata.labels["atomi.cloud/service"] == "carbon") and
  (map(select(.kind != "PlatformDependency")) | length == 0)
' <<<"${primordial_json}" >/dev/null || {
  echo "❌ primordial chart must contain exactly the unique platform-shared PlatformDependency set" >&2
  exit 1
}

echo "✅ Carbon rendered-resource contract passed"
