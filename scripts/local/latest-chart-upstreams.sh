#!/usr/bin/env bash
# ### aluminium-latest-upstreams
# #### source: aluminium
# Resolve the latest real upstream chart and image tags:
#   - chart: grafana/k8s-monitoring (HTTP helm repo)
#   - image: grafana/alloy (the collector runtime)
set -euo pipefail

grafana_repo_url='https://grafana.github.io/helm-charts'
if ! helm repo list 2>/dev/null | rg -q 'grafana\s+grafana-helm-charts|grafana\s+https://grafana.github.io/helm-charts'; then
  helm repo add grafana "${grafana_repo_url}" >/dev/null
fi
helm repo update grafana >/dev/null 2>&1 || true

chart_tag="$(helm search repo grafana/k8s-monitoring --versions -o json | jq -r 'sort_by(.version) | .[0].version' 2>/dev/null | tail -n 1)"
image_tag="$(skopeo list-tags docker://docker.io/grafana/alloy | jq -r '.Tags[]' | rg -v 'latest|main|master|rc|alpha|beta' | sort -V | tail -n 1)"

[ -z "${chart_tag}" ] && echo "❌ no grafana/k8s-monitoring chart tags resolved" >&2 && exit 1
[ -z "${image_tag}" ] && echo "❌ no grafana/alloy image tags resolved" >&2 && exit 1

echo "📦 latest chart tag:  grafana/k8s-monitoring ${chart_tag}"
echo "📦 latest image tag:  grafana/alloy ${image_tag}"
echo "✅ Upstream tags resolved"
