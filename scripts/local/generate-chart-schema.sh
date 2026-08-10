#!/usr/bin/env bash
set -euo pipefail

output="${1:-chart/values.schema.json}"
output_abs="$(realpath -m "${output}")"

(cd chart && helm-schema --use-helm-docs --schema-root.title 'Diene Chlorine Values' --schema-root.description 'Generated schema for the diene chlorine stakater/reloader wrapper chart.' --values values.yaml --output "${output_abs}")

echo "✅ Chart values schema generated at ${output}"
