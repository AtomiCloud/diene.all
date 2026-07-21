#!/usr/bin/env bash
set -euo pipefail

chart="${1:-chart}"
output="${2:-${chart}/values.schema.json}"
output_abs="$(realpath -m "${output}")"

(cd "${chart}" && helm-schema --use-helm-docs --schema-root.title 'Diene Carbon Values' --schema-root.description 'Generated schema for one chart in the diene carbon app and primordial pair.' --values values.yaml --output "${output_abs}")

echo "✅ ${chart} values schema generated at ${output}"
