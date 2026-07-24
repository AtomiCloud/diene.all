#!/usr/bin/env bash
set -euo pipefail

version="${1:-}"
[ -z "${version}" ] && echo "❌ version argument not set" >&2 && exit 1

printf '%s\n' "${version#v}" >VERSION
yq eval -i ".version = \"${version#v}\"" chart/Chart.yaml

echo "✅ VERSION and chart manifest stamped to ${version#v}"
