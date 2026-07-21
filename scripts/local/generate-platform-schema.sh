#!/usr/bin/env bash
set -euo pipefail

output="${1:-platform.schema.json}"
jq --indent 2 --sort-keys . platform.schema.source.json >"${output}"

echo "✅ Carbon platform schema generated at ${output}"
