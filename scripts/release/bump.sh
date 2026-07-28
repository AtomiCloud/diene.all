#!/usr/bin/env bash
set -euo pipefail

version="${1:-}"
[ -z "${version}" ] && echo "❌ version argument not set" >&2 && exit 1

printf '%s\n' "${version#v}" >VERSION
yq eval -i ".version = \"${version#v}\"" chart/Chart.yaml
yq eval -i ".appVersion = \"${version#v}\"" chart/Chart.yaml
yq eval -i ".image.tag = \"${version#v}\"" chart/values.yaml
yq eval -i ".version = \"${version#v}\"" primordial-chart/Chart.yaml
yq eval -i ".appVersion = \"${version#v}\"" primordial-chart/Chart.yaml

echo "✅ VERSION and both Lithium chart manifests stamped to ${version#v}"
