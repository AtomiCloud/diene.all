#!/usr/bin/env bash
set -euo pipefail

root_dir="$(git rev-parse --show-toplevel)"
cd "${root_dir}"

echo "🚀 Running the Go consumer worker against the local stack..."
./scripts/local/with-dev-env.sh go run ./cmd/go-consumer worker "$@"
echo "✅ Go consumer worker stopped"
