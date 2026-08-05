#!/usr/bin/env bash
set -euo pipefail

go test -run '^$' ./lib/... ./adapters/... ./cmd/go-base

echo "✅ Go source packages typecheck"
