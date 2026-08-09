#!/usr/bin/env bash
set -euo pipefail

root_dir="$(git rev-parse --show-toplevel)"
cd "${root_dir}"

./scripts/local/compile.sh
echo "🔎 Running the compiled Bun consumer..."
./scripts/local/with-dev-env.sh ./dist/bin/bun-consumer "$@"
echo "✅ Compiled Bun consumer run completed"
