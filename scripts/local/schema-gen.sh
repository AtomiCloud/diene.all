#!/usr/bin/env bash
set -euo pipefail

root_dir="$(git rev-parse --show-toplevel)"
cd "${root_dir}"

echo "🧬 Generating Bun consumer configuration schema..."
bun run ./scripts/local/schema-gen.ts "$@"
echo "✅ Configuration schema generated"
