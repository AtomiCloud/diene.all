#!/usr/bin/env bash
set -euo pipefail

mode="${1:-}"
target="${2:-}"
extra="${3:-}"

[ -z "${mode}" ] && echo "❌ assertion mode not set" >&2 && exit 1

case "${mode}" in
directory-map)
  [ -z "${target}" ] && echo "❌ chart directory not set" >&2 && exit 1
  production='https://acme-v02.api.letsencrypt.org/directory'
  staging='https://acme-staging-v02.api.letsencrypt.org/directory'
  for landscape in pikachu raichu amphoros; do
    [ "$(yq -r '.serviceTree.landscape' "${target}/values.${landscape}.yaml")" != "${landscape}" ] && echo "❌ ${landscape} overlay identity mismatch" >&2 && exit 1
    [ "$(yq -r '.issuer.server' "${target}/values.${landscape}.yaml")" != "${production}" ] && echo "❌ ${landscape} must use the Let's Encrypt production directory" >&2 && exit 1
  done
  for landscape in pichu lapras; do
    [ "$(yq -r '.serviceTree.landscape' "${target}/values.${landscape}.yaml")" != "${landscape}" ] && echo "❌ ${landscape} overlay identity mismatch" >&2 && exit 1
    [ "$(yq -r '.issuer.server' "${target}/values.${landscape}.yaml")" != "${staging}" ] && echo "❌ ${landscape} must use the Let's Encrypt staging directory" >&2 && exit 1
  done
  ;;

entei-render)
  [ -z "${target}" ] && echo "❌ rendered manifest not set" >&2 && exit 1
  yq eval-all -o=json '.' "${target}" |
    jq -s -e '
      [ .[] | select(.kind == "ClusterIssuer") ] as $issuers |
      ($issuers | length == 2) and
      ([$issuers[].metadata.name] | sort == ["zinc-production", "zinc-staging"]) and
      ([$issuers[] | select(.metadata.name == "zinc-staging") | .spec.acme.server] == ["https://acme-staging-v02.api.letsencrypt.org/directory"]) and
      ([$issuers[] | select(.metadata.name == "zinc-production") | .spec.acme.server] == ["https://acme-v02.api.letsencrypt.org/directory"]) and
      ([$issuers[].spec.acme.solvers[0].selector.dnsZones | sort] | all(. == ["eevee.dev.atomi.cloud", "entei.dev.atomi.cloud", "minun.dev.atomi.cloud", "plusle.dev.atomi.cloud"]))
    ' >/dev/null
  ;;

cardinality)
  [ -z "${target}" ] && echo "❌ rendered manifest not set" >&2 && exit 1
  [ -z "${extra}" ] && echo "❌ expected issuer count not set" >&2 && exit 1
  yq eval-all -o=json '.' "${target}" |
    jq -s -e --argjson expected "${extra}" '[.[] | select(.kind == "ClusterIssuer")] | length == $expected' >/dev/null
  ;;

no-certificates)
  [ -z "${target}" ] && echo "❌ rendered manifest not set" >&2 && exit 1
  yq eval-all -o=json '.' "${target}" |
    jq -s -e '[.[] | select(.kind == "Certificate")] | length == 0' >/dev/null
  ;;

external-secret)
  [ -z "${target}" ] && echo "❌ rendered manifest not set" >&2 && exit 1
  yq eval-all -o=json '.' "${target}" |
    jq -s -e '
      [ .[] | select(.kind == "ExternalSecret") ] as $secrets |
      [ .[] | select(.kind == "ClusterIssuer") ] as $issuers |
      ($secrets | length == 1) and
      ($secrets[0].metadata.name == "zinc-cloudflare") and
      ($secrets[0].spec.target == {"name":"zinc-cloudflare","creationPolicy":"Owner"}) and
      (($secrets[0].spec.data // []) | length == 0) and
      ($secrets[0].spec.dataFrom == [{"find":{"path":"/shared/cloudflare/dns01"},"rewrite":[{"regexp":{"source":"(.*)","target":"SHARED_$1"}}]}]) and
      ($issuers | length > 0) and
      ($issuers | all(.spec.acme.solvers[0].dns01.cloudflare.apiTokenSecretRef == {"name":"zinc-cloudflare","key":"SHARED_API_TOKEN"}))
    ' >/dev/null
  ;;

lpsm)
  [ -z "${target}" ] && echo "❌ rendered manifest not set" >&2 && exit 1
  [ -z "${extra}" ] && echo "❌ label prefix not set" >&2 && exit 1
  yq eval-all -o=json '.' "${target}" |
    jq -s -e --arg prefix "${extra}" '
      map(select(.kind != null)) | length > 0 and all(.[].metadata;
        .labels[$prefix + "/platform"] == "sample" and
        .labels[$prefix + "/service"] == "zinc" and
        .labels[$prefix + "/module"] == "issuer" and
        .labels[$prefix + "/layer"] == "1" and
        .annotations[$prefix + "/platform"] == "sample" and
        .annotations[$prefix + "/service"] == "zinc" and
        .annotations[$prefix + "/module"] == "issuer" and
        .annotations[$prefix + "/layer"] == "1")
    ' >/dev/null
  ;;

no-literal-credentials)
  [ -z "${target}" ] && echo "❌ source directory not set" >&2 && exit 1
  if rg -n --glob '*.yaml' --glob '*.yml' '^[[:space:]]*(apiToken|token|password|clientSecret):[[:space:]]*[^#[:space:]]' "${target}" >/dev/null; then
    echo "❌ inline credential literal found" >&2
    exit 1
  fi
  ;;

k3d-script)
  [ -z "${target}" ] && echo "❌ k3d proof script not set" >&2 && exit 1
  rg -q 'K3D_ISOLATE_BY_PATH' "${target}"
  rg -q 'K3D_REQUIRE_OWNERSHIP=true' "${target}"
  rg -q -- '--kube-context "k3d-\$\{cluster_name\}"' "${target}"
  rg -q 'cert-manager\.crds\.yaml' "${target}"
  rg -q 'clusterissuers\.cert-manager\.io' "${target}"
  rg -q 'kind: Certificate' "${target}"
  rg -q 'issuerRef:' "${target}"
  ;;

*)
  echo "❌ unknown assertion mode '${mode}'" >&2
  exit 1
  ;;
esac

echo "✅ zinc ${mode} assertion passed"
