#!/usr/bin/env bash
# ### aluminium-latest-upstreams
# #### source: aluminium
# Resolve the latest real upstream chart and image tags:
#   - chart: grafana/k8s-monitoring (HTTP helm repo)
#   - image: grafana/alloy (the collector runtime)
set -euo pipefail

grafana_repo_url='https://grafana.github.io/helm-charts'
chart_search_json="${ALUMINIUM_HELM_SEARCH_JSON:-}"
image_tags_json="${ALUMINIUM_IMAGE_TAGS_JSON:-}"

if [ -z "${chart_search_json}" ]; then
  if ! helm repo list 2>/dev/null | rg -q 'grafana\s+grafana-helm-charts|grafana\s+https://grafana.github.io/helm-charts'; then
    helm repo add grafana "${grafana_repo_url}" >/dev/null
  fi
  helm repo update grafana >/dev/null 2>&1
  chart_search_json="$(helm search repo grafana/k8s-monitoring --versions -o json)"
fi

if [ -z "${image_tags_json}" ]; then
  image_tags_json="$(skopeo list-tags docker://docker.io/grafana/alloy)"
fi

chart_tag="$(printf '%s' "${chart_search_json}" | jq -r '.[].version' | LC_ALL=C sort -V | tail -n 1)"
image_tag="$(printf '%s' "${image_tags_json}" | jq -r '.Tags[]' | rg -v 'latest|main|master|rc|alpha|beta' | LC_ALL=C sort -V | tail -n 1)"

[ -z "${chart_tag}" ] && echo "❌ no grafana/k8s-monitoring chart tags resolved" >&2 && exit 1
[ -z "${image_tag}" ] && echo "❌ no grafana/alloy image tags resolved" >&2 && exit 1

echo "📦 latest chart tag:  grafana/k8s-monitoring ${chart_tag}"
echo "📦 latest image tag:  grafana/alloy ${image_tag}"
echo "✅ Upstream tags resolved"
