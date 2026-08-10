#!/usr/bin/env bash
set -euo pipefail

mode="${1:-build}"
repo_root="$(git rev-parse --show-toplevel)"
chart_dir="${repo_root}/chart"
version="$(yq -r '.dependencies[] | select(.name == "metrics-server") | .version' "${chart_dir}/Chart.yaml")"
evidence="${chart_dir}/upstream-evidence.yaml"
expected_version="$(yq -r '.chart.version' "${evidence}")"
expected_app="$(yq -r '.chart.appVersion' "${evidence}")"
expected_source_sha="$(yq -r '.chart.sourceArchiveSha256' "${evidence}")"
expected_patched_sha="$(yq -r '.chart.patchedArchiveSha256' "${evidence}")"
patch_file="${repo_root}/$(yq -r '.chart.patch' "${evidence}")"
archive="${chart_dir}/charts/metrics-server-${version}.tgz"
tmp="$(mktemp -d)"
trap 'rm -rf "${tmp}"' EXIT

[ "${mode}" != "build" ] && [ "${mode}" != "update" ] && echo "❌ mode must be build or update" >&2 && exit 1
[ "${version}" != "${expected_version}" ] && echo "❌ dependency ${version} does not match upstream evidence ${expected_version}" >&2 && exit 1

if [ "${mode}" = "update" ]; then
  helm dependency update "${chart_dir}"
elif [ ! -s "${archive}" ]; then
  helm dependency build "${chart_dir}"
fi

[ ! -s "${archive}" ] && echo "❌ metrics-server archive ${archive} is missing" >&2 && exit 1
actual_source_sha="$(sha256sum "${archive}" | awk '{print $1}')"
tar -xzf "${archive}" -C "${tmp}"
archive_version="$(yq -r '.version' "${tmp}/metrics-server/Chart.yaml")"
archive_app="$(yq -r '.appVersion' "${tmp}/metrics-server/Chart.yaml")"
[ "${archive_version}" != "${expected_version}" ] && echo "❌ archive chart version ${archive_version} is not ${expected_version}" >&2 && exit 1
[ "${archive_app}" != "${expected_app}" ] && echo "❌ archive app version ${archive_app} is not ${expected_app}" >&2 && exit 1

if [ "${actual_source_sha}" = "${expected_source_sha}" ]; then
  patch -d "${tmp}/metrics-server" -p 1 <"${patch_file}"
  tar --sort=name --mtime='UTC 1970-01-01' --owner=0 --group=0 --numeric-owner \
    -C "${tmp}" -cf - metrics-server | gzip -n >"${archive}.tmp"
  mv "${archive}.tmp" "${archive}"
elif ! patch --dry-run -R -d "${tmp}/metrics-server" -p 1 <"${patch_file}" >/dev/null; then
  echo "❌ vendored archive is neither the recorded upstream nor the expected patched chart" >&2
  exit 1
fi

rm -rf "${tmp}/metrics-server"
mkdir -p "${tmp}/verify"
tar -xzf "${archive}" -C "${tmp}/verify"
patch --dry-run -R -d "${tmp}/verify/metrics-server" -p 1 <"${patch_file}" >/dev/null
actual_patched_sha="$(sha256sum "${archive}" | awk '{print $1}')"
[ "${actual_patched_sha}" != "${expected_patched_sha}" ] && echo "❌ patched archive sha256 ${actual_patched_sha} is not ${expected_patched_sha}" >&2 && exit 1

echo "✅ metrics-server ${version}/${expected_app} dependency vendored with the xenon integration patch"
