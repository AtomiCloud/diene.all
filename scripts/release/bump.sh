#!/usr/bin/env bash
set -euo pipefail

version="${1:-}"
[ -z "${version}" ] && echo "❌ version argument not set" >&2 && exit 1

# The parent removed the workspace-tier `VERSION` file and nothing else in this
# node reads it, so the two chart manifests are the version source of truth.
yq eval -i ".version = \"${version#v}\"" chart/Chart.yaml
yq eval -i ".appVersion = \"${version#v}\"" chart/Chart.yaml
yq eval -i ".image.tag = \"${version#v}\"" chart/values.yaml
yq eval -i ".version = \"${version#v}\"" primordial-chart/Chart.yaml
yq eval -i ".appVersion = \"${version#v}\"" primordial-chart/Chart.yaml

helm-docs --chart-search-root chart
helm-docs --chart-search-root primordial-chart

echo "✅ both Lithium chart manifests and generated docs stamped to ${version#v}"
