#!/usr/bin/env bash
set -euo pipefail

# Resolve the latest cert-manager chart and controller image tags.
#
# The cert-manager chart is served from the jetstack HTTP helm repo (resolved via
# helm); the controller image lives on quay.io/jetstack (resolved via skopeo).
# The chart and image share one version, so both must resolve to matching tags.
# Network reachability is required — this task is a smoke (functional) check,
# not part of the offline unit tier.

helm repo add jetstack https://charts.jetstack.io >/dev/null 2>&1 || true
helm repo update jetstack >/dev/null 2>&1 || true
chart_tag="$(helm search repo jetstack/cert-manager --versions -o json 2>/dev/null |
  jq -r '.[].version' | sort -V | tail -n 1 || true)"
image_tag="$(skopeo list-tags docker://quay.io/jetstack/cert-manager-controller 2>/dev/null |
  jq -r '.Tags[]' | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -n 1 || true)"

[ -z "${chart_tag}" ] && echo "❌ no cert-manager chart tag resolved (is the jetstack repo reachable?)" >&2 && exit 1
[ -z "${image_tag}" ] && echo "❌ no cert-manager controller image tag resolved (is quay.io reachable?)" >&2 && exit 1

echo "📦 latest chart tag: ${chart_tag}"
echo "📦 latest controller image tag: ${image_tag}"
echo "✅ Upstream tags resolved"
