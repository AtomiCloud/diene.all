#!/usr/bin/env bash
set -euo pipefail

go test -run '^$' ./...

echo "✅ Go source packages typecheck"
