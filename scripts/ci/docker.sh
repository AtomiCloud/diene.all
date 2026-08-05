#!/usr/bin/env bash
set -euo pipefail

push="${CI_DOCKER_PUSH:-false}"
version="${RELEASE_VERSION:-}"

[ -z "${CI_DOCKER_CONTEXT:-}" ] && echo "❌ 'CI_DOCKER_CONTEXT' env var not set" >&2 && exit 1
[ -z "${CI_DOCKER_IMAGE:-}" ] && echo "❌ 'CI_DOCKER_IMAGE' env var not set" >&2 && exit 1
[ -z "${CI_DOCKERFILE:-}" ] && echo "❌ 'CI_DOCKERFILE' env var not set" >&2 && exit 1

# Pushing needs a registry, a credential and the ref metadata that names the tags.
# The local build needs none of it, so the condition is stated once here rather than
# repeated as a prefix on every guard. The names are a list because that is what they
# are; `${!var}` reads each one by name and `:-` keeps `set -u` out of it.
if [ "${push}" = "true" ]; then
  for var in \
    CI_DOCKER_PLATFORM \
    DOMAIN \
    DOCKER_PASSWORD \
    DOCKER_USER \
    GITHUB_BRANCH \
    GITHUB_REPO_REF \
    GITHUB_SHA \
    LATEST_BRANCH; do
    [ -n "${!var:-}" ] || {
      echo "❌ '${var}' env var not set" >&2
      exit 1
    }
  done
fi

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
