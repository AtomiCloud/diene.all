#!/usr/bin/env bash
set -euo pipefail

output="${1:-chart/values.schema.json}"
output_abs="$(realpath -m "${output}")"

(cd chart && helm-schema --use-helm-docs --schema-root.title 'Vanadium Values' --schema-root.description 'Generated schema for the vanadium ValidatingAdmissionPolicy chart.' --values values.yaml --output "${output_abs}")

jq '
  .properties.policies.properties |= with_entries(
    .value.properties.actions = {
      type: "array",
      minItems: 1,
      uniqueItems: true,
      items: {type: "string", enum: ["Warn", "Audit", "Deny"]},
      oneOf: [
        {const: ["Warn", "Audit"]},
        {const: ["Deny"]}
      ]
    }
  )
' "${output_abs}" >"${output_abs}.tmp"
mv "${output_abs}.tmp" "${output_abs}"

echo "✅ Chart values schema generated at ${output}"
