#!/usr/bin/env bash
set -euo pipefail

root_dir="$(git rev-parse --show-toplevel)"
cd "${root_dir}"

echo "🚀 Running the Bun consumer source entry..."
./scripts/local/with-dev-env.sh bun run ./src/index.ts -- "$@"
echo "✅ Bun consumer source run completed"
