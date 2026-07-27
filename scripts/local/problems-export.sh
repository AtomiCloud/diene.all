#!/usr/bin/env bash
set -euo pipefail

root_dir="$(git rev-parse --show-toplevel)"
cd "${root_dir}"

echo "📚 Exporting the Go consumer Problem catalog..." >&2
go run ./scripts/local/problemsexport "$@"
echo "✅ Go consumer Problem catalog exported" >&2
