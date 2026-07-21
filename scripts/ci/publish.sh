#!/usr/bin/env bash
set -euo pipefail

./scripts/validate/manifest-tag.sh

[ -z "${PUB_CREDENTIALS_JSON:-}" ] && echo "❌ PUB_CREDENTIALS_JSON env var not set" >&2 && exit 1
pub_cache="${PUB_CACHE:-${HOME}/.pub-cache}"
mkdir -p "${pub_cache}"
printf '%s' "${PUB_CREDENTIALS_JSON}" >"${pub_cache}/credentials.json"
chmod 600 "${pub_cache}/credentials.json"

dart pub publish --force
