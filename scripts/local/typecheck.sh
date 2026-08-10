#!/usr/bin/env bash
set -euo pipefail

go test -run '^$' ./lib/... ./adapters/... ./testhelper/...

echo "✅ Go source packages typecheck"
