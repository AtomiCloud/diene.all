#!/usr/bin/env bash
set -euo pipefail

go test -run '^$' ./lib/... ./testhelper/...

echo "✅ Go source packages typecheck"
