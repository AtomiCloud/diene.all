#!/usr/bin/env bash
# Resolve the latest real upstream stakater/reloader chart and ghcr.io/stakater
# image tags and check them against the recorded selection evidence. chlorine is
# pinned AT the recorded latest, so this asserts (1) the pinned release matches
# the recorded selection and (2) upstream has not regressed BELOW the pin — a
# genuinely newer upstream is an informational note, not a failure (adopting it
# is a `dep(reloader)` PR), so a mid-window upstream release does not red CI.
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
evidence="${repo_root}/chart/upstream-evidence.yaml"
repository="$(yq -r '.chart.repository' "${evidence}")"
expected_chart="$(yq -r '.chart.version' "${evidence}")"
expected_app="$(yq -r '.chart.appVersion' "${evidence}")"
expected_image="$(yq -r '.image.selectedTag' "${evidence}")"
controller_repo="$(yq -r '.image.controllerRepository' "${evidence}")"
pinned_chart="$(yq -r '.dependencies[] | select(.name == "reloader") | .version' "${repo_root}/chart/Chart.yaml")"
pinned_app="$(yq -r '.appVersion' "${repo_root}/chart/Chart.yaml")"
tmp="$(mktemp -d)"
trap 'rm -rf "${tmp}"' EXIT

not_older() { # not_older A B  → true when A is >= B under version sort
  [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | tail -n 1)" = "$1" ]
}

HELM_REPOSITORY_CONFIG="${tmp}/repositories.yaml" HELM_REPOSITORY_CACHE="${tmp}/cache" \
  helm repo add reloader "${repository}" >/dev/null
latest_chart_json="$(HELM_REPOSITORY_CONFIG="${tmp}/repositories.yaml" HELM_REPOSITORY_CACHE="${tmp}/cache" \
  helm search repo reloader/reloader --versions --output json | jq -c '.[0]')"
latest_chart="$(printf '%s' "${latest_chart_json}" | jq -r '.version')"
latest_chart_app="$(printf '%s' "${latest_chart_json}" | jq -r '.app_version')"
latest_image="$(skopeo list-tags "docker://${controller_repo}" | jq -r '.Tags[] | select(test("^v[0-9]+[.][0-9]+[.][0-9]+$"))' | sort -V | tail -n 1)"

# The pinned release must match the recorded selection exactly.
[ "${pinned_chart}" != "${expected_chart}" ] && echo "❌ pinned chart ${pinned_chart} is not selected ${expected_chart}" >&2 && exit 1
[ "${pinned_app}" != "${expected_app}" ] && echo "❌ pinned app ${pinned_app} is not selected ${expected_app}" >&2 && exit 1
[ "${expected_image}" != "${expected_app}" ] && echo "❌ selected image ${expected_image} does not match selected app ${expected_app}" >&2 && exit 1

# Upstream must not have regressed below the pin.
not_older "${latest_chart}" "${pinned_chart}" || {
  echo "❌ official latest chart ${latest_chart} is older than the pinned ${pinned_chart}" >&2
  exit 1
}
not_older "${latest_image}" "${expected_image}" || {
  echo "❌ official latest image ${latest_image} is older than the pinned ${expected_image}" >&2
  exit 1
}

echo "📦 official latest chart: ${latest_chart} (app ${latest_chart_app})"
echo "📦 official latest image: ${latest_image}"
echo "📦 selected pinned release: chart ${pinned_chart} / app ${pinned_app} / image ${expected_image}"
if [ "${latest_chart}" != "${expected_chart}" ]; then
  echo "ℹ️  upstream has advanced past the pin since evidence was recorded (${expected_chart} → ${latest_chart}); adopt via a dep(reloader) PR"
fi
echo "✅ Upstream evidence matches the official repositories (pinned at recorded latest)"
