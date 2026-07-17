#!/usr/bin/env bash
set -euo pipefail

push="${CI_DOCKER_PUSH:-false}"
version="${RELEASE_VERSION:-}"

[ -z "${CI_DOCKER_CONTEXT:-}" ] && echo "❌ 'CI_DOCKER_CONTEXT' env var not set" >&2 && exit 1
[ -z "${CI_DOCKER_IMAGE:-}" ] && echo "❌ 'CI_DOCKER_IMAGE' env var not set" >&2 && exit 1
[ -z "${CI_DOCKERFILE:-}" ] && echo "❌ 'CI_DOCKERFILE' env var not set" >&2 && exit 1
[ "${push}" = "true" ] && [ -z "${CI_DOCKER_PLATFORM:-}" ] && echo "❌ 'CI_DOCKER_PLATFORM' env var not set" >&2 && exit 1
[ "${push}" = "true" ] && [ -z "${DOMAIN:-}" ] && echo "❌ 'DOMAIN' env var not set" >&2 && exit 1
[ "${push}" = "true" ] && [ -z "${DOCKER_PASSWORD:-}" ] && echo "❌ 'DOCKER_PASSWORD' env var not set" >&2 && exit 1
[ "${push}" = "true" ] && [ -z "${DOCKER_USER:-}" ] && echo "❌ 'DOCKER_USER' env var not set" >&2 && exit 1
[ "${push}" = "true" ] && [ -z "${GITHUB_BRANCH:-}" ] && echo "❌ 'GITHUB_BRANCH' env var not set" >&2 && exit 1
[ "${push}" = "true" ] && [ -z "${GITHUB_REPO_REF:-}" ] && echo "❌ 'GITHUB_REPO_REF' env var not set" >&2 && exit 1
[ "${push}" = "true" ] && [ -z "${GITHUB_SHA:-}" ] && echo "❌ 'GITHUB_SHA' env var not set" >&2 && exit 1
[ "${push}" = "true" ] && [ -z "${LATEST_BRANCH:-}" ] && echo "❌ 'LATEST_BRANCH' env var not set" >&2 && exit 1

if [ "${push}" = "true" ]; then
  echo "${DOCKER_PASSWORD}" | docker login "${DOMAIN}" -u "${DOCKER_USER}" --password-stdin
  image_id="$(echo "${DOMAIN}/${GITHUB_REPO_REF}/${CI_DOCKER_IMAGE}" | tr '[:upper:]' '[:lower:]')"
  sha="$(echo "${GITHUB_SHA}" | head -c 6)"
  branch="${GITHUB_BRANCH//[._]/-}"
  branch="${branch//\//-}"
  image_version="${sha}-${branch}"
  latest_arg="$([ "${branch}" = "${LATEST_BRANCH}" ] && echo "-t ${image_id}:latest" || true)"
  semver_arg="$([ -n "${version}" ] && echo "-t ${image_id}:${version}" || true)"
  echo "🔨 Building and pushing ${image_id}"
  # shellcheck disable=SC2086
  docker buildx build "${CI_DOCKER_CONTEXT}" -f "${CI_DOCKERFILE}" --platform="${CI_DOCKER_PLATFORM}" --push -t "${image_id}:${image_version}" -t "${image_id}:${branch}" ${latest_arg} ${semver_arg}
else
  echo "🔨 Building ${CI_DOCKER_IMAGE}:local"
  docker build "${CI_DOCKER_CONTEXT}" -f "${CI_DOCKERFILE}" -t "${CI_DOCKER_IMAGE}:local"
fi

echo "✅ Docker build complete"
