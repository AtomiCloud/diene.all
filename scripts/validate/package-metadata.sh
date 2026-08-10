#!/usr/bin/env bash
set -euo pipefail

# Package metadata gate: the manifest metadata and the root LICENSE must agree.
manifest="package.json"
license_file="LICENSE"

[ ! -f "${manifest}" ] && echo "❌ '${manifest}' is missing" >&2 && exit 1
[ ! -f "${license_file}" ] && echo "❌ root '${license_file}' is missing" >&2 && exit 1

declared="$(jq -r '.license // ""' "${manifest}")"
[ -z "${declared}" ] && echo "❌ '${manifest}' declares no license" >&2 && exit 1

# The SPDX identifier in the manifest must match the license the root file grants.
license_kind=""
head -n 1 "${license_file}" | grep -qi 'MIT License' && license_kind="MIT"
[ -z "${license_kind}" ] && echo "❌ could not recognise the license kind from '${license_file}'" >&2 && exit 1
[ "${declared}" != "${license_kind}" ] && echo "❌ manifest license '${declared}' != root LICENSE kind '${license_kind}'" >&2 && exit 1

echo "✅ package metadata: manifest license '${declared}' agrees with root LICENSE"
