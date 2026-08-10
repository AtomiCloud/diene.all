#!/usr/bin/env bash
# Reusable provider × landscape toggle predicate. An optional replacement lets
# the caller run the same checker against the lapras OFF→ON negative fixture.
set -euo pipefail

map_file="${1:-chart/toggle-map.yaml}"
release="${RELEASE:-xenon}"
namespace="${NAMESPACE:-sample}"
replace_path="${TOGGLE_REPLACE_PATH:-}"
replace_with="${TOGGLE_REPLACE_WITH:-}"
matrix_json="$(yq -o=json '.' "${map_file}")"
replacement_used=false

printf '%s' "${matrix_json}" | jq -e '
  ([.providers[].provider] | sort) == ["doks", "eks-auto", "eks-classic", "k3s", "onprem"]
  and ([.landscapes[].landscape] | sort) == ["lapras", "onprem", "pichu", "pikachu", "raichu"]
  and (all(.providers[]; (.landscapes | length) > 0))
  and (all(.landscapes[]; (.overlays | length) > 0))
  and (all(.providers[] | select(.provider != "k3s"); (.preinstalled == false and .enabled == true)))
  and ((.providers[] | select(.provider == "k3s")) | (.preinstalled == true and .enabled == false and .landscapes == ["lapras"]))
  and ([.providers[].landscapes[]] | unique | sort) == ([.landscapes[].landscape] | sort)
' >/dev/null

while IFS= read -r matrix_entry; do
  provider="$(printf '%s' "${matrix_entry}" | jq -r '.provider')"
  landscape="$(printf '%s' "${matrix_entry}" | jq -r '.landscape')"
  provider_expected="$(printf '%s' "${matrix_entry}" | jq -r '.enabled')"
  landscape_entry="$(printf '%s' "${matrix_json}" | jq -c --arg landscape "${landscape}" '.landscapes[] | select(.landscape == $landscape)')"
  landscape_expected="$(printf '%s' "${landscape_entry}" | jq -r '.enabled')"
  [ "${provider_expected}" != "${landscape_expected}" ] && echo "❌ ${provider}/${landscape} expectations disagree" >&2 && exit 1

  helm_args=()
  while IFS= read -r overlay; do
    selected_overlay="${overlay}"
    if [ -n "${replace_path}" ] && [ "${overlay}" = "${replace_path}" ]; then
      selected_overlay="${replace_with}"
      replacement_used=true
    fi
    [ ! -s "${selected_overlay}" ] && echo "❌ overlay ${selected_overlay} is missing" >&2 && exit 1
    helm_args+=(--values "${selected_overlay}")
  done < <(printf '%s' "${landscape_entry}" | jq -r '.overlays[]')

  rendered="$(helm template "${release}" chart --namespace "${namespace}" "${helm_args[@]}")"
  resource_count="$(printf '%s\n' "${rendered}" | rg -c '^kind:' || true)"
  resource_count="${resource_count:-0}"
  [ "${resource_count}" -gt 0 ] && actual=true || actual=false
  [ "${actual}" != "${provider_expected}" ] && echo "❌ toggle mismatch for ${provider}/${landscape}: expected=${provider_expected} actual=${actual} resources=${resource_count}" >&2 && exit 1
done < <(printf '%s' "${matrix_json}" | jq -c '.providers[] as $provider | $provider.landscapes[] | {provider: $provider.provider, enabled: $provider.enabled, landscape: .}')

if [ -n "${replace_path}" ] && [ "${replacement_used}" != "true" ]; then
  echo "❌ replacement overlay ${replace_path} was not exercised" >&2
  exit 1
fi

exit 0
