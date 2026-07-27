#!/usr/bin/env bash
set -euo pipefail

# Build-phase chart vendoring. Helm cannot read files outside a chart directory
# and rejects out-of-chart symlinks, so the authoritative repository-root
# `observability/` is COPIED into the primordial chart before lint, template,
# package, or publish. The copy is gitignored, regenerated every build, and
# never hand-edited.

chart="infra/primordial_chart"

[ -d observability ] && echo "📦 vendoring observability/ into ${chart}/files/"

rm -rf "${chart}/files/observability"
mkdir -p "${chart}/files"
cp -r observability "${chart}/files/observability"

echo "✅ Chart vendoring complete"
