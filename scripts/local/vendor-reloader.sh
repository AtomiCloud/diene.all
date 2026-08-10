#!/usr/bin/env bash
# Vendor the pinned upstream stakater/reloader chart (pure passthrough — no patch).
# Verifies the vendored archive is exactly the recorded upstream source archive.
set -euo pipefail

mode="${1:-build}"
repo_root="$(git rev-parse --show-toplevel)"
chart_dir="${repo_root}/chart"
evidence="${chart_dir}/upstream-evidence.yaml"
version="$(yq -r '.dependencies[] | select(.name == "reloader") | .version' "${chart_dir}/Chart.yaml")"
expected_version="$(yq -r '.chart.version' "${evidence}")"
expected_app="$(yq -r '.chart.appVersion' "${evidence}")"
expected_source_sha="$(yq -r '.chart.sourceArchiveSha256' "${evidence}")"
archive="${chart_dir}/charts/reloader-${version}.tgz"
tmp="$(mktemp -d)"
trap 'rm -rf "${tmp}"' EXIT

[ "${mode}" != "build" ] && [ "${mode}" != "update" ] && echo "❌ mode must be build or update" >&2 && exit 1
[ "${version}" != "${expected_version}" ] && echo "❌ dependency ${version} does not match upstream evidence ${expected_version}" >&2 && exit 1

if [ "${mode}" = "update" ]; then
  helm dependency update "${chart_dir}"
elif [ ! -s "${archive}" ]; then
  helm dependency build "${chart_dir}"
fi

[ ! -s "${archive}" ] && echo "❌ reloader archive ${archive} is missing" >&2 && exit 1
actual_source_sha="$(sha256sum "${archive}" | awk '{print $1}')"
[ "${actual_source_sha}" != "${expected_source_sha}" ] && echo "❌ vendored archive sha256 ${actual_source_sha} is not the recorded upstream ${expected_source_sha}" >&2 && exit 1

tar -xzf "${archive}" -C "${tmp}"
archive_version="$(yq -r '.version' "${tmp}/reloader/Chart.yaml")"
archive_app="$(yq -r '.appVersion' "${tmp}/reloader/Chart.yaml")"
[ "${archive_version}" != "${expected_version}" ] && echo "❌ archive chart version ${archive_version} is not ${expected_version}" >&2 && exit 1
[ "${archive_app}" != "${expected_app}" ] && echo "❌ archive app version ${archive_app} is not ${expected_app}" >&2 && exit 1

echo "✅ reloader ${version}/${expected_app} dependency vendored (pure passthrough, upstream archive)"
