#!/usr/bin/env bash
set -euo pipefail

push="${CI_HELM_PUSH:-false}"
version="${RELEASE_VERSION:-}"
version="${version#v}"

[ -z "${CHART_PATH:-}" ] && echo "❌ 'CHART_PATH' env var not set" >&2 && exit 1
[ "${push}" = "true" ] && [ -z "${version}" ] && echo "❌ chart publication requires RELEASE_VERSION" >&2 && exit 1
[ "${push}" = "true" ] && [ -z "${DOMAIN:-}" ] && echo "❌ 'DOMAIN' env var not set" >&2 && exit 1
[ "${push}" = "true" ] && [ -z "${DOCKER_PASSWORD:-}" ] && echo "❌ 'DOCKER_PASSWORD' env var not set" >&2 && exit 1
[ "${push}" = "true" ] && [ -z "${DOCKER_USER:-}" ] && echo "❌ 'DOCKER_USER' env var not set" >&2 && exit 1

echo "📦 Validating chart ${CHART_PATH}..."
helm lint "${CHART_PATH}"
helm template mercury "${CHART_PATH}" >/dev/null

if [[ ${push} == "true" ]]; then
  output_dir="dist/helm/$(basename "${CHART_PATH}")"
  oci_ref="$(echo "oci://${DOMAIN}/${GITHUB_REPOSITORY_OWNER}" | tr '[:upper:]' '[:lower:]')"
  mkdir -p "${output_dir}"
  echo "${DOCKER_PASSWORD}" | helm registry login "${DOMAIN}" -u "${DOCKER_USER}" --password-stdin
  helm package "${CHART_PATH}" --version "${version}" --app-version "${version}" --destination "${output_dir}"
  package="$(find "${output_dir}" -maxdepth 1 -name '*.tgz' -print -quit)"
  [ -z "${package}" ] && echo "❌ packaged chart was not produced" >&2 && exit 1
  helm push "${package}" "${oci_ref}"
  echo "🔏 Signing immutable chart package with GitHub OIDC..."
  docker run --rm \
    -e ACTIONS_ID_TOKEN_REQUEST_TOKEN \
    -e ACTIONS_ID_TOKEN_REQUEST_URL \
    -e COSIGN_EXPERIMENTAL=1 \
    -v "${PWD}:/workspace" \
    -w /workspace \
    ghcr.io/sigstore/cosign/cosign:v2.4.3 sign-blob --yes --bundle "/workspace/${package}.bundle" "/workspace/${package}"
  echo "chart-package=${package}" >>"${GITHUB_OUTPUT:-/dev/null}"
fi
echo "✅ Helm validation complete"
