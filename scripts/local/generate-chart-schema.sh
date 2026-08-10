#!/usr/bin/env bash
set -euo pipefail

output="${1:-chart/values.schema.json}"
output_abs="$(realpath -m "${output}")"

(cd chart && helm-schema --use-helm-docs --schema-root.title 'Diene Xenon Values' --schema-root.description 'Generated schema for the diene xenon conditional metrics-server chart.' --values values.yaml --output "${output_abs}")

echo "✅ Chart values schema generated at ${output}"
