#!/usr/bin/env bash
set -euo pipefail

push="${CI_DOCKER_PUSH:-false}"
version="${RELEASE_VERSION:-}"
version="${version#v}"
platforms="${CI_DOCKER_PLATFORM:-linux/amd64}"
trivy_image="aquasec/trivy:0.58.2"

[ -z "${CI_DOCKER_CONTEXT:-}" ] && echo "❌ 'CI_DOCKER_CONTEXT' env var not set" >&2 && exit 1
[ -z "${CI_DOCKER_IMAGE:-}" ] && echo "❌ 'CI_DOCKER_IMAGE' env var not set" >&2 && exit 1
[ -z "${CI_DOCKERFILE:-}" ] && echo "❌ 'CI_DOCKERFILE' env var not set" >&2 && exit 1
[ "${push}" = "true" ] && [ -z "${version}" ] && echo "❌ release publication requires RELEASE_VERSION" >&2 && exit 1
[ "${push}" = "true" ] && [ -z "${DOMAIN:-}" ] && echo "❌ 'DOMAIN' env var not set" >&2 && exit 1
[ "${push}" = "true" ] && [ -z "${DOCKER_PASSWORD:-}" ] && echo "❌ 'DOCKER_PASSWORD' env var not set" >&2 && exit 1
[ "${push}" = "true" ] && [ -z "${DOCKER_USER:-}" ] && echo "❌ 'DOCKER_USER' env var not set" >&2 && exit 1

workdir="$(mktemp -d)"
trap 'rm -rf "${workdir}"' EXIT

# Build and vulnerability-scan EVERY target platform as an immutable local artifact
# BEFORE any registry push. Each platform is exported to its own single-platform
# archive and scanned from that exact artifact, so the scan can never resolve only
# the runner architecture and no tag/manifest is published until every platform passes.
IFS=',' read -ra platform_list <<<"${platforms}"
scanned=0
for platform in "${platform_list[@]}"; do
  platform="${platform//[[:space:]]/}"
  [ -z "${platform}" ] && continue
  slug="${platform//\//-}"
  archive="${workdir}/${slug}.tar"
  echo "🔨 Building immutable ${platform} artifact for pre-publication scan..."
  docker buildx build "${CI_DOCKER_CONTEXT}" \
    --file "${CI_DOCKERFILE}" \
    --platform "${platform}" \
    --output "type=docker,dest=${archive}"
  echo "🔎 Scanning immutable ${platform} artifact for fixable high and critical vulnerabilities..."
  docker run --rm -v "${workdir}:/scan:ro" "${trivy_image}" \
    image --exit-code 1 --ignore-unfixed --severity HIGH,CRITICAL --input "/scan/${slug}.tar"
  scanned=$((scanned + 1))
done
[ "${scanned}" -eq 0 ] && echo "❌ no target platform was built or scanned" >&2 && exit 1
echo "✅ All ${scanned} target platform artifact scans passed"

if [[ ${push} != "true" ]]; then
  echo "✅ Container build and per-platform scan passed (no publication requested)"
  exit 0
fi

# Every target platform scan passed. Publish the multi-arch manifest with SBOM and
# provenance, then sign the immutable published digest. Registry manifest assembly is
# NOT transactional: the CD pre-publication barrier and the post-publish immutable-set
# verification make any partial publication detectable, and Kargo's equal-semver guard
# refuses to promote a mismatched set. We do not claim atomic publication here.
image_ref="$(echo "${DOMAIN}/${CI_DOCKER_IMAGE}:${version}" | tr '[:upper:]' '[:lower:]')"
metadata="${workdir}/metadata.json"
echo "${DOCKER_PASSWORD}" | docker login "${DOMAIN}" -u "${DOCKER_USER}" --password-stdin
echo "📦 Publishing multi-arch image ${image_ref} with SBOM and provenance..."
docker buildx build "${CI_DOCKER_CONTEXT}" \
  --file "${CI_DOCKERFILE}" \
  --platform "${platforms}" \
  --tag "${image_ref}" \
  --attest type=sbom \
  --attest type=provenance,mode=max \
  --metadata-file "${metadata}" \
  --push
digest="$(jq -r '."containerimage.digest"' "${metadata}")"
[ -z "${digest}" ] || [ "${digest}" = "null" ] && echo "❌ image digest missing from build metadata" >&2 && exit 1
echo "image-ref=${image_ref}" >>"${GITHUB_OUTPUT:-/dev/null}"
echo "image-digest=${digest}" >>"${GITHUB_OUTPUT:-/dev/null}"

echo "🔏 Signing immutable image digest with GitHub OIDC..."
docker run --rm \
  -e ACTIONS_ID_TOKEN_REQUEST_TOKEN \
  -e ACTIONS_ID_TOKEN_REQUEST_URL \
  -e COSIGN_EXPERIMENTAL=1 \
  -v "${DOCKER_CONFIG:-${HOME}/.docker}:/root/.docker:ro" \
  ghcr.io/sigstore/cosign/cosign:v2.4.3 sign --yes "${image_ref}@${digest}"
echo "✅ Container build, per-platform scan, publish, and signature complete"
