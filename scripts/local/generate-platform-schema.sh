#!/usr/bin/env bash
set -euo pipefail

# Generate the diene-platform compiler chart's values.schema.json from its
# annotated values.yaml, mirroring scripts/local/generate-chart-schema.sh for
# the helm-wrapper chart. The schema-drift gate regenerates into a temp file and
# compares, so this stays the single source of truth for the committed schema.

chart="registry/charts/diene-platform"
output="${1:-${chart}/values.schema.json}"
output_abs="$(realpath -m "${output}")"

(cd "${chart}" && helm-schema \
  --use-helm-docs \
  --schema-root.title 'Diene Platform Compiler Values' \
  --schema-root.description 'Generated schema for the diene-platform compiler chart (source A defaults + platform.yaml + services.yaml).' \
  --values values.yaml \
  --output "${output_abs}")

echo "✅ diene-platform values schema generated at ${output}"
