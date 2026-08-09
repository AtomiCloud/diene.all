#!/usr/bin/env bash
set -euo pipefail

push="${CI_HELM_PUSH:-false}"
version="${RELEASE_VERSION:-}"

[ -z "${CHART_PATH:-}" ] && echo "❌ 'CHART_PATH' env var not set" >&2 && exit 1
[ "${push}" = "true" ] && [ -z "${DOMAIN:-}" ] && echo "❌ 'DOMAIN' env var not set" >&2 && exit 1
[ "${push}" = "true" ] && [ -z "${DOCKER_PASSWORD:-}" ] && echo "❌ 'DOCKER_PASSWORD' env var not set" >&2 && exit 1
[ "${push}" = "true" ] && [ -z "${DOCKER_USER:-}" ] && echo "❌ 'DOCKER_USER' env var not set" >&2 && exit 1
[ "${push}" = "true" ] && [ -z "${GITHUB_BRANCH:-}" ] && echo "❌ 'GITHUB_BRANCH' env var not set" >&2 && exit 1
[ "${push}" = "true" ] && [ -z "${GITHUB_REPO_REF:-}" ] && echo "❌ 'GITHUB_REPO_REF' env var not set" >&2 && exit 1
[ "${push}" = "true" ] && [ -z "${GITHUB_SHA:-}" ] && echo "❌ 'GITHUB_SHA' env var not set" >&2 && exit 1

helm lint "${CHART_PATH}"
helm template diene-go-base "${CHART_PATH}" >/dev/null

if [ "${push}" = "true" ]; then
  sha="$(echo "${GITHUB_SHA}" | head -c 6)"
  branch="${GITHUB_BRANCH//[._]/-}"
  branch="${branch//\//-}"
  commit_version="${sha}-${branch}"
  helm_version="${version:-v0.0.0-${commit_version}}"
  image_version="${version:-${commit_version}}"
  oci_ref="$(echo "oci://${DOMAIN}/${GITHUB_REPO_REF}" | tr '[:upper:]' '[:lower:]')"
  yq eval ".appVersion = \"${image_version}\"" "${CHART_PATH}/Chart.yaml" >"${CHART_PATH}/Chart.yaml.tmp"
  mv "${CHART_PATH}/Chart.yaml.tmp" "${CHART_PATH}/Chart.yaml"
  echo "${DOCKER_PASSWORD}" | helm registry login "${DOMAIN}" -u "${DOCKER_USER}" --password-stdin
  helm dependency build "${CHART_PATH}"
  helm package "${CHART_PATH}" -u --version "${helm_version}" --app-version "${image_version}" -d "${CHART_PATH}/uploads"
  for filename in "${CHART_PATH}"/uploads/*.tgz; do
    helm push "${filename}" "${oci_ref}"
  done
  rm -rf "${CHART_PATH}/uploads"
fi

echo "✅ Helm validation complete"
