#!/usr/bin/env bash
set -euo pipefail

mode="${PUBLISH_MODE:-git}"
dry_run="${PUBLISH_DRY_RUN:-true}"
release_version="${RELEASE_VERSION:-}"
output_dir="${PUBLISH_OUTPUT_DIR:-dist/${mode}}"
oci_registry="${OCI_REGISTRY:-}"
oci_repository="${OCI_REPOSITORY:-charts}"
plain_http="${OCI_PLAIN_HTTP:-false}"
oci_username="${OCI_USERNAME:-}"
oci_password="${OCI_PASSWORD:-}"

[ -z "${release_version}" ] && echo "❌ 'RELEASE_VERSION' env var not set" >&2 && exit 1
[ "${mode}" != "git" ] && [ "${mode}" != "oci" ] && echo "❌ PUBLISH_MODE must be git or oci" >&2 && exit 1

version="${release_version#v}"
manifest_version="$(yq -r '.version' chart/Chart.yaml)"
[ "${manifest_version}" != "${version}" ] && echo "❌ Chart version ${manifest_version} does not match tag ${version}" >&2 && exit 1

bash ./scripts/ci/setup.sh
helm-docs --chart-search-root chart
mkdir -p "${output_dir}"
helm dependency build chart
helm package chart --destination "${output_dir}" --version "${version}"
chart_name="$(yq -r '.name' chart/Chart.yaml)"
package="${output_dir}/${chart_name}-${version}.tgz"
[ ! -s "${package}" ] && echo "❌ chart package was not created" >&2 && exit 1

if [ "${mode}" = "git" ]; then
  helm repo index "${output_dir}"
  [ ! -s "${output_dir}/index.yaml" ] && echo "❌ git chart-repository index was not created" >&2 && exit 1
fi

if [ "${mode}" = "oci" ]; then
  [ -z "${oci_registry}" ] && [ "${dry_run}" != "true" ] && echo "❌ 'OCI_REGISTRY' env var not set" >&2 && exit 1
  oci_ref="oci://${oci_registry:-registry.example.invalid}/${oci_repository}"
  printf '%s\n' "${oci_ref}" >"${output_dir}/oci-ref.txt"
  if [ "${dry_run}" != "true" ]; then
    if [ -n "${oci_username}" ] || [ -n "${oci_password}" ]; then
      [ -z "${oci_username}" ] && echo "❌ 'OCI_USERNAME' env var not set" >&2 && exit 1
      [ -z "${oci_password}" ] && echo "❌ 'OCI_PASSWORD' env var not set" >&2 && exit 1
      printf '%s' "${oci_password}" | helm registry login "${oci_registry}" --username "${oci_username}" --password-stdin
    fi
    push_args=()
    [ "${plain_http}" = "true" ] && push_args+=(--plain-http)
    helm push "${package}" "${oci_ref}" "${push_args[@]}"
  fi
fi

[ "${dry_run}" = "true" ] && result="dry-run" || result="round-trip"
echo "✅ ${mode} chart publish ${result} complete for ${version}"
