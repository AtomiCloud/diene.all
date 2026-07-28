#!/usr/bin/env bash
set -euo pipefail

version="${1:-}"
[ -z "${version}" ] && echo "❌ version argument not set" >&2 && exit 1

git restore --source=HEAD -- Version.props
xmlstarlet ed --inplace -u '/Project/PropertyGroup/Version' -v "${version#v}" Version.props

echo "✅ Version.props stamped to ${version#v}"
