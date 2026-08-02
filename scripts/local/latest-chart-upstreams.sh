#!/usr/bin/env bash
set -euo pipefail

chart_tag="$(skopeo list-tags docker://ghcr.io/stefanprodan/charts/podinfo | jq -r '.Tags[] | select(test("^[0-9]+\\.[0-9]+\\.[0-9]+$"))' | sort -V | tail -n 1)"
image_tag="$(skopeo list-tags docker://ghcr.io/stefanprodan/podinfo | jq -r '.Tags[] | select(test("^[0-9]+\\.[0-9]+\\.[0-9]+([._-][A-Za-z0-9.-]+)?$"))' | sort -V | tail -n 1)"

[ -z "${chart_tag}" ] && echo "❌ no Podinfo chart tags resolved" >&2 && exit 1
[ -z "${image_tag}" ] && echo "❌ no Podinfo image tags resolved" >&2 && exit 1

echo "📦 latest chart tag: ${chart_tag}"
echo "📦 latest image tag: ${image_tag}"
echo "✅ Upstream tags resolved"
