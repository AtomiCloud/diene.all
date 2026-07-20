#!/usr/bin/env bash
set -euo pipefail

[ -z "${GITHUB_REF_NAME:-}" ] && echo "❌ GITHUB_REF_NAME must be set to the pushed v*.*.* tag" >&2 && exit 1

version="${GITHUB_REF_NAME#v}"
manifest_version="$(xmlstarlet sel -t -v '/Project/PropertyGroup/Version' Version.props)"
[ "${manifest_version}" != "${version}" ] && echo "❌ Version.props version (${manifest_version}) != tag version (${version})" >&2 && exit 1

echo "✅ Version.props matches tag ${GITHUB_REF_NAME}"
