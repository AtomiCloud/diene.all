#!/usr/bin/env bash
set -euo pipefail

tmp="$(mktemp)"
trap 'rm -f "${tmp}"' EXIT
bun tool/generate-config-schema.ts >"${tmp}"
mv "${tmp}" config/schema.json
trap - EXIT

echo "✅ Flutter configuration schema generated"
