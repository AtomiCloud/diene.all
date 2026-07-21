#!/usr/bin/env bash
set -euo pipefail

# AUTHORED pub.dev publish path (conductor-gated — NOT executed at this node).
# Run on a tagged release after CI is green: it enforces the manifest==tag
# guard, then publishes to pub.dev using the PUB_CREDENTIALS_JSON secret.
#
# Usage: publish.sh <tag>
# Requires: PUB_CREDENTIALS_JSON in the environment (the pub.dev credential
# class, GitHub secret) and a clean git tree at the tagged commit.

tag="${1:-}"
[ -z "${tag}" ] && echo "❌ tag argument not set" >&2 && exit 1

# Fail closed unless the manifest exactly matches the tag being published.
./scripts/release/verify-manifest.sh "${tag}"

if [ -z "${PUB_CREDENTIALS_JSON:-}" ]; then
  echo "❌ PUB_CREDENTIALS_JSON not set — cannot authenticate to pub.dev" >&2
  exit 1
fi

# Install the pub.dev credentials for the tool cache, then publish.
config_dir="${PUB_CACHE:-${HOME}/.pub-cache}"
mkdir -p "${config_dir}"
printf '%s' "${PUB_CREDENTIALS_JSON}" >"${config_dir}/credentials.json"

echo "📦 Publishing diene_e2e ${tag} to pub.dev..."
dart pub publish --force

echo "✅ Published diene_e2e ${tag}"
