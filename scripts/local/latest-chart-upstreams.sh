#!/usr/bin/env bash
set -euo pipefail

# Resolve the latest External Secrets Operator upstream tag. ESO chart version
# tracks the operator image appVersion, so the image tag is the upstream signal.
image_tags="$(skopeo list-tags docker://ghcr.io/external-secrets/external-secrets | jq -r '.Tags[] | select(test("^v[0-9]+\\.[0-9]+\\.[0-9]+$"))' | sort -V | tail -n 1)"

[ -z "${image_tags}" ] && echo "❌ no External Secrets Operator image tags resolved" >&2 && exit 1

echo "📦 latest external-secrets tag: ${image_tags}"
echo "✅ Upstream tags resolved"
