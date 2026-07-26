#!/usr/bin/env bash
set -euo pipefail

root_dir="$(git rev-parse --show-toplevel)"
cd "${root_dir}"

echo "🚀 Running the Go consumer source entry..."
./scripts/local/with-dev-env.sh go run ./cmd/go-consumer "$@"
echo "✅ Go consumer source run completed"
