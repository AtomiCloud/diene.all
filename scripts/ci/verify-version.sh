#!/usr/bin/env bash
set -euo pipefail

# Publish version guard (M1): the release commit already stamped the manifest;
# this verifies package.json .version == ${GITHUB_REF_NAME#v} and NEVER mutates.
root_dir="$(git rev-parse --show-toplevel)"
cd "${root_dir}"

[ -z "${GITHUB_REF_NAME:-}" ] && echo "❌ GITHUB_REF_NAME must be set (the pushed tag, e.g. v1.2.3)" >&2 && exit 1

version="${GITHUB_REF_NAME#v}"
manifest="$(jq -r .version package.json)"

if [ "${manifest}" != "${version}" ]; then
  echo "❌ package.json version (${manifest}) != tag version (${version})" >&2
  exit 1
fi

echo "✅ package.json is stamped with ${version}"
