#!/usr/bin/env bash
set -euo pipefail

chart_tags="$(skopeo list-tags docker://ghcr.io/stakater/charts/reloader | jq -r '.Tags[]' | sort -V | tail -n 1)"
image_tags="$(skopeo list-tags docker://ghcr.io/stakater/reloader | jq -r '.Tags[]' | sort -V | tail -n 1)"

[ -z "${chart_tags}" ] && echo "❌ no Reloader chart tags resolved" >&2 && exit 1
[ -z "${image_tags}" ] && echo "❌ no Reloader image tags resolved" >&2 && exit 1

echo "📦 latest chart tag: ${chart_tags}"
echo "📦 latest image tag: ${image_tags}"
echo "✅ Upstream tags resolved"
