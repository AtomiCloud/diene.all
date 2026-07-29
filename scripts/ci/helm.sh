#!/usr/bin/env bash
set -euo pipefail

push="${CI_HELM_PUSH:-false}"
version="${RELEASE_VERSION:-}"
charts="${CHART_PATHS:-${CHART_PATH:-}}"

[ -z "${charts}" ] && echo "❌ neither 'CHART_PATHS' nor 'CHART_PATH' env var is set" >&2 && exit 1
[ "${push}" = "true" ] && [ -z "${DOMAIN:-}" ] && echo "❌ 'DOMAIN' env var not set" >&2 && exit 1
[ "${push}" = "true" ] && [ -z "${DOCKER_PASSWORD:-}" ] && echo "❌ 'DOCKER_PASSWORD' env var not set" >&2 && exit 1
[ "${push}" = "true" ] && [ -z "${DOCKER_USER:-}" ] && echo "❌ 'DOCKER_USER' env var not set" >&2 && exit 1
[ "${push}" = "true" ] && [ -z "${GITHUB_BRANCH:-}" ] && echo "❌ 'GITHUB_BRANCH' env var not set" >&2 && exit 1
[ "${push}" = "true" ] && [ -z "${GITHUB_REPO_REF:-}" ] && echo "❌ 'GITHUB_REPO_REF' env var not set" >&2 && exit 1
[ "${push}" = "true" ] && [ -z "${GITHUB_SHA:-}" ] && echo "❌ 'GITHUB_SHA' env var not set" >&2 && exit 1

# R20 ships TWO charts — the runtime app chart and the primordial CR chart. They are
# validated and published by ONE invocation so that a single semver reaches both; two
# independent runs could disagree the moment one of them was retried.
read -r -a chart_list <<<"${charts}"
echo "📝 charts under management: ${#chart_list[@]} (${charts})"

linted=0
for chart in "${chart_list[@]}"; do
  [ ! -d "${chart}" ] && echo "❌ chart path '${chart}' does not exist" >&2 && exit 1
  [ ! -f "${chart}/Chart.yaml" ] && echo "❌ '${chart}' has no Chart.yaml" >&2 && exit 1
  # The release name is the chart's own name, never a literal: a hardcoded name renders a
  # different service than the one being published (R4).
  name="$(yq -r '.name // ""' "${chart}/Chart.yaml")"
  [ -z "${name}" ] && echo "❌ '${chart}/Chart.yaml' declares no name" >&2 && exit 1
  echo "🔨 linting and rendering '${name}' from ${chart}"
  helm lint "${chart}"
  helm template "${name}" "${chart}" >/dev/null
  linted=$((linted + 1))
done

echo "📝 linted and rendered ${linted}/${#chart_list[@]} chart(s)"
[ "${linted}" -ne "${#chart_list[@]}" ] && echo "❌ not every chart was validated" >&2 && exit 1

if [ "${push}" = "true" ]; then
  sha="$(echo "${GITHUB_SHA}" | head -c 6)"
  branch="${GITHUB_BRANCH//[._]/-}"
  branch="${branch//\//-}"
  commit_version="${sha}-${branch}"
  helm_version="${version:-v0.0.0-${commit_version}}"
  image_version="${version:-${commit_version}}"
  oci_ref="$(echo "oci://${DOMAIN}/${GITHUB_REPO_REF}" | tr '[:upper:]' '[:lower:]')"

  # ONE semver spans the image tag, both chart versions, and both appVersions. Kargo reads
  # chart Version == image Tag, so these two values are deliberately the same string.
  echo "📝 release version '${helm_version}', app version '${image_version}' for every chart"

  echo "🔐 logging in to ${DOMAIN}"
  echo "${DOCKER_PASSWORD}" | helm registry login "${DOMAIN}" -u "${DOCKER_USER}" --password-stdin

  pushed=0
  for chart in "${chart_list[@]}"; do
    yq eval ".appVersion = \"${image_version}\"" "${chart}/Chart.yaml" >"${chart}/Chart.yaml.tmp"
    mv "${chart}/Chart.yaml.tmp" "${chart}/Chart.yaml"
    helm dependency build "${chart}"
    helm package "${chart}" -u --version "${helm_version}" --app-version "${image_version}" -d "${chart}/uploads"
    for filename in "${chart}"/uploads/*.tgz; do
      echo "📤 pushing $(basename "${filename}") to ${oci_ref}"
      helm push "${filename}" "${oci_ref}"
      pushed=$((pushed + 1))
    done
    rm -rf "${chart}/uploads"
  done

  echo "📦 pushed ${pushed} package(s) at version ${helm_version} (appVersion ${image_version})"
  [ "${pushed}" -lt "${#chart_list[@]}" ] && echo "❌ fewer packages pushed than charts" >&2 && exit 1
fi

echo "✅ Helm validation complete for ${linted} chart(s)"
