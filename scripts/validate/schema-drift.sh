#!/usr/bin/env bash
set -euo pipefail

root_dir="$(git rev-parse --show-toplevel)"
cd "${root_dir}"
generated="$(mktemp)"
trap 'rm -f "${generated}"' EXIT

echo "🧬 Checking generated configuration schema..."
bun run ./scripts/local/schema-gen.ts --out "${generated}"
cmp --silent schemas/bun-consumer.schema.json "${generated}" || {
  echo "❌ Configuration schema drifted; run ./scripts/local/schema-gen.sh" >&2
  exit 1
}
echo "✅ Configuration schema is current"
