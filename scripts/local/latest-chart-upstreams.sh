#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
evidence="${repo_root}/chart/upstream-evidence.yaml"
repository="$(yq -r '.chart.repository' "${evidence}")"
expected_chart="$(yq -r '.chart.version' "${evidence}")"
expected_app="$(yq -r '.chart.appVersion' "${evidence}")"
expected_image="$(yq -r '.image.selectedTag' "${evidence}")"
expected_latest_image="$(yq -r '.image.observedLatestTag' "${evidence}")"
pinned_chart="$(yq -r '.dependencies[] | select(.name == "metrics-server") | .version' "${repo_root}/chart/Chart.yaml")"
pinned_app="$(yq -r '.appVersion' "${repo_root}/chart/Chart.yaml")"
tmp="$(mktemp -d)"
trap 'rm -rf "${tmp}"' EXIT

HELM_REPOSITORY_CONFIG="${tmp}/repositories.yaml" HELM_REPOSITORY_CACHE="${tmp}/cache" \
  helm repo add metrics-server "${repository}" >/dev/null
latest_chart_json="$(HELM_REPOSITORY_CONFIG="${tmp}/repositories.yaml" HELM_REPOSITORY_CACHE="${tmp}/cache" \
  helm search repo metrics-server/metrics-server --versions --output json | jq -c '.[0]')"
latest_chart="$(printf '%s' "${latest_chart_json}" | jq -r '.version')"
latest_chart_app="$(printf '%s' "${latest_chart_json}" | jq -r '.app_version')"
latest_image="$(skopeo list-tags docker://registry.k8s.io/metrics-server/metrics-server | jq -r '.Tags[] | select(test("^v[0-9]+[.][0-9]+[.][0-9]+$"))' | sort -V | tail -n 1)"

[ "${latest_chart}" != "${expected_chart}" ] && echo "❌ official latest chart ${latest_chart} is not recorded ${expected_chart}" >&2 && exit 1
[ "${latest_chart_app}" != "${expected_app}" ] && echo "❌ official chart app ${latest_chart_app} is not recorded ${expected_app}" >&2 && exit 1
[ "${latest_image}" != "${expected_latest_image}" ] && echo "❌ latest image ${latest_image} is not recorded ${expected_latest_image}" >&2 && exit 1
[ "${pinned_chart}" != "${expected_chart}" ] && echo "❌ pinned chart ${pinned_chart} is not selected ${expected_chart}" >&2 && exit 1
[ "${pinned_app}" != "${expected_app}" ] && echo "❌ pinned app ${pinned_app} is not selected ${expected_app}" >&2 && exit 1
[ "${expected_image}" != "v${expected_app}" ] && echo "❌ selected image ${expected_image} does not match selected app v${expected_app}" >&2 && exit 1

echo "📦 official latest chart: ${latest_chart} (app ${latest_chart_app})"
echo "📦 official latest image: ${latest_image}"
echo "📦 selected compatible release: chart ${pinned_chart} / app ${pinned_app} / image ${expected_image}"
echo "✅ Upstream evidence matches the official repositories"
