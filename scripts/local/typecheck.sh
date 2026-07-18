#!/usr/bin/env bash
set -euo pipefail

go test -run '^$' ./lib/... ./adapters/... ./cmd/...

echo "✅ Go source packages typecheck"
