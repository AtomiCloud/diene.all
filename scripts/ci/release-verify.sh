#!/usr/bin/env bash
set -euo pipefail

require_input() {
  local name="${1}"
  if [[ -z ${!name:-} ]]; then
    echo "❌ required release verification input ${name} is unset" >&2
    exit 2
  fi
}

for name in DOMAIN DOCKER_USER DOCKER_PASSWORD OWNER RELEASE_VERSION; do
  require_input "${name}"
done

version="${RELEASE_VERSION#v}"
semver_core='(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)'
semver_identifier='(0|[1-9][0-9]*|[0-9]*[A-Za-z-][0-9A-Za-z-]*)'
semver_pattern="^${semver_core}(-${semver_identifier}(\\.${semver_identifier})*)?$"
if [[ ! ${version} =~ ${semver_pattern} ]]; then
  echo "❌ RELEASE_VERSION must be an OCI-compatible SemVer, optionally prefixed with v" >&2
  exit 2
fi
if [[ ! ${DOMAIN} =~ ^[A-Za-z0-9.-]+(:[0-9]+)?$ ]]; then
  echo "❌ DOMAIN must be a registry hostname with an optional port" >&2
  exit 2
fi

normalized_owner="$(tr '[:upper:]' '[:lower:]' <<<"${OWNER}")"
if [[ ! ${normalized_owner} =~ ^[a-z0-9]+([._-][a-z0-9]+)*$ ]]; then
  echo "❌ OWNER is not a valid lowercase registry path component" >&2
  exit 2
fi

credentials="${DOCKER_USER}:${DOCKER_PASSWORD}"
image="ghcr.io/atomicloud/diene.mercury:${version}"
app="${DOMAIN}/${normalized_owner}/mercury-webhook:${version}"
primordial="${DOMAIN}/${normalized_owner}/mercury-webhook-primordial:${version}"

echo "🔎 Verifying multi-arch image manifest ${image}..."
if ! image_raw="$(skopeo inspect --creds "${credentials}" --raw "docker://${image}" 2>/dev/null)"; then
  echo "❌ image ${image} is absent; partial publication detected for ${version}" >&2
  exit 1
fi
for want in linux/amd64 linux/arm64; do
  if ! jq -e --arg os "${want%/*}" --arg arch "${want#*/}" \
    '.manifests[]?.platform | select(.os == $os and .architecture == $arch)' \
    <<<"${image_raw}" >/dev/null; then
    echo "❌ image ${image} is missing required platform ${want}; partial publication detected for ${version}" >&2
    exit 1
  fi
done

echo "🔎 Verifying app chart ${app}..."
if ! skopeo inspect --creds "${credentials}" --raw "docker://${app}" >/dev/null 2>&1; then
  echo "❌ app chart ${app} is absent; partial publication detected for ${version}" >&2
  exit 1
fi

echo "🔎 Verifying primordial chart ${primordial}..."
if ! skopeo inspect --creds "${credentials}" --raw "docker://${primordial}" >/dev/null 2>&1; then
  echo "❌ primordial chart ${primordial} is absent; partial publication detected for ${version}" >&2
  exit 1
fi

echo "✅ Complete immutable set present for ${version}: image (linux/amd64, linux/arm64), app chart, primordial chart"
