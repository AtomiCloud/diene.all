#!/usr/bin/env bash
set -euo pipefail

# The metrics-server image is the skopeo-resolvable upstream artifact; the chart
# ships on a Helm HTTP repository (not OCI), so the pinned chart version is read
# from the dependency declaration rather than resolved over the registry.
image_tags="$(skopeo list-tags docker://registry.k8s.io/metrics-server/metrics-server | jq -r '.Tags[] | select(test("^v[0-9]+\\.[0-9]+\\.[0-9]+$"))' | sort -V | tail -n 1)"
chart_version="$(yq -r '.dependencies[] | select(.name == "metrics-server") | .version' chart/Chart.yaml)"

[ -z "${image_tags}" ] && echo "❌ no metrics-server image tags resolved" >&2 && exit 1
[ -z "${chart_version}" ] && echo "❌ no metrics-server chart version pinned" >&2 && exit 1

echo "📦 latest image tag: ${image_tags}"
echo "📦 pinned chart version: ${chart_version}"
echo "✅ Upstream tags resolved"
