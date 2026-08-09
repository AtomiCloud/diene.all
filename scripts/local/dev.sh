#!/usr/bin/env bash
set -euo pipefail

root_dir="$(git rev-parse --show-toplevel)"
cd "${root_dir}"

echo "♻️ Starting the Bun consumer watch loop..."
./scripts/local/with-dev-env.sh bun --watch run ./src/index.ts -- worker "$@"
echo "✅ Bun consumer watch loop stopped"
