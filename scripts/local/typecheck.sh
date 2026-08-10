#!/usr/bin/env bash
set -euo pipefail

go test -run '^$' ./lib/...

echo "✅ Go source packages typecheck"
