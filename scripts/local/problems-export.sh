#!/usr/bin/env bash
set -euo pipefail

root_dir="$(git rev-parse --show-toplevel)"
cd "${root_dir}"

echo "📚 Exporting the Problem catalog..." >&2
bun run ./scripts/local/problems-export.ts "$@"
echo "✅ Problem catalog exported" >&2
