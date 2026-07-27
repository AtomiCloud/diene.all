#!/usr/bin/env bash
set -euo pipefail

root_dir="$(git rev-parse --show-toplevel)"
cd "${root_dir}"

echo "🧬 Generating Go consumer configuration schema..."
go run ./scripts/local/schemagen "$@"
echo "✅ Configuration schema generated"
