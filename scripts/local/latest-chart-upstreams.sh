#!/usr/bin/env bash
set -euo pipefail

chart_tags="$(skopeo list-tags docker://cr.kgateway.dev/kgateway-dev/charts/kgateway | jq -r '.Tags[]' | sort -V | tail -n 1)"
crd_tags="$(skopeo list-tags docker://cr.kgateway.dev/kgateway-dev/charts/kgateway-crds | jq -r '.Tags[]' | sort -V | tail -n 1)"
image_tags="$(skopeo list-tags docker://cr.kgateway.dev/kgateway-dev/kgateway | jq -r '.Tags[]' | sort -V | tail -n 1)"

[ -z "${chart_tags}" ] && echo "❌ no kgateway chart tags resolved" >&2 && exit 1
[ -z "${crd_tags}" ] && echo "❌ no kgateway-crds chart tags resolved" >&2 && exit 1
[ -z "${image_tags}" ] && echo "❌ no kgateway image tags resolved" >&2 && exit 1

echo "📦 latest kgateway chart tag: ${chart_tags}"
echo "📦 latest kgateway-crds chart tag: ${crd_tags}"
echo "📦 latest kgateway image tag: ${image_tags}"
echo "✅ Upstream tags resolved"
