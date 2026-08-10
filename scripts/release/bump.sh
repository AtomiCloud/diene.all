#!/usr/bin/env bash
set -euo pipefail

version="${1:-}"
[ -z "${version}" ] && echo "❌ version argument not set" >&2 && exit 1

# The parent removed the workspace-tier `VERSION` file and nothing else in this
# node reads it, so the chart manifest is the only thing this node versions.
# `chart/README.md` carries the version badge helm-docs renders out of
# `chart/Chart.yaml`, so it is regenerated here rather than left to drift and
# turn `a-wrapper-helm-docs` red on the next commit.
yq eval -i ".version = \"${version#v}\"" chart/Chart.yaml
helm-docs --chart-search-root chart

echo "✅ chart manifest and generated chart docs stamped to ${version#v}"
