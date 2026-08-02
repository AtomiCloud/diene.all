#!/usr/bin/env bash
set -euo pipefail

# OCI is the primary distribution channel, so it is what an omitted PUBLISH_MODE
# selects. The git chart repository stays supported as the secondary channel, but
# only when it is asked for by name.
mode="${PUBLISH_MODE:-oci}"
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
[ "${oci_repository}" != "${oci_repository,,}" ] && echo "❌ OCI_REPOSITORY must be lowercase, got '${oci_repository}'" >&2 && exit 1

version="${release_version#v}"
manifest_version="$(yq -r '.version' chart/Chart.yaml)"
[ "${manifest_version}" != "${version}" ] && echo "❌ Chart version ${manifest_version} does not match tag ${version}" >&2 && exit 1

bash ./scripts/ci/setup.sh
bash ./scripts/local/vendor-chart-config.sh
helm-docs --chart-search-root chart

# The pinned dependency archives are vendored under `chart/charts` and tracked in
# git. `helm dependency build` discards and re-pulls every one of them from the
# upstream OCI registry on each run, so packaging — a dry run included — would need
# the public network for archives this repository already carries. Verify the
# vendored state locally instead. Chart.lock's `digest` exists to detect a lock that
# has drifted from the manifest it was resolved from; comparing the pins themselves
# asserts that same property without re-resolving them over the network.
dependency_pins() {
  yq -o=json -I=0 \
    '[.dependencies[]? | {"name": .name, "version": .version, "repository": .repository}] | sort_by(.name, .version)' \
    "$1"
}

manifest_pins="$(dependency_pins chart/Chart.yaml)"
locked_pins="$(dependency_pins chart/Chart.lock)"
if [ "${manifest_pins}" != "${locked_pins}" ]; then
  echo "❌ chart/Chart.lock does not pin what chart/Chart.yaml declares" >&2
  echo "   Chart.yaml: ${manifest_pins}" >&2
  echo "   Chart.lock: ${locked_pins}" >&2
  exit 1
fi

# Exact set equality, not mere presence: an archive the lock does not name is still
# packaged into the released chart, so a leftover from an older pin has to be a
# failure rather than dead weight that ships.
expected_archives="$(yq -r '.dependencies[]? | .name + "-" + .version + ".tgz"' chart/Chart.lock | LC_ALL=C sort)"
present_archives="$(find chart/charts -mindepth 1 -maxdepth 1 -name '*.tgz' -printf '%f\n' 2>/dev/null | LC_ALL=C sort)"
if [ "${expected_archives}" != "${present_archives}" ]; then
  echo "❌ chart/charts does not hold exactly the archives chart/Chart.lock pins" >&2
  echo "   expected: ${expected_archives//$'\n'/ }" >&2
  echo "   present: ${present_archives//$'\n'/ }" >&2
  exit 1
fi

# A file named for the pin is not proof of the pin: read the chart metadata out of
# each archive so a renamed or re-vendored tarball cannot pass as the locked one.
while IFS='|' read -r dep_name dep_version; do
  [ -z "${dep_name}" ] && continue
  archive="chart/charts/${dep_name}-${dep_version}.tgz"
  [ ! -s "${archive}" ] && echo "❌ vendored dependency archive '${archive}' is missing or empty" >&2 && exit 1
  packaged="$(helm show chart "${archive}" | yq -r '.name + "-" + .version')"
  [ "${packaged}" != "${dep_name}-${dep_version}" ] &&
    echo "❌ '${archive}' packages ${packaged}, not the locked ${dep_name}-${dep_version}" >&2 && exit 1
done < <(yq -r '.dependencies[]? | .name + "|" + .version' chart/Chart.lock)

mkdir -p "${output_dir}"
helm package chart --destination "${output_dir}" --version "${version}"
package="${output_dir}/diene-helm-wrapper-${version}.tgz"
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
