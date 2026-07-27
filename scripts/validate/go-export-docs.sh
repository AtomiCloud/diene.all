#!/usr/bin/env bash
set -euo pipefail

golangci-lint run --config .golangci.docs.yaml ./...

echo "✅ Every exported Go symbol is documented"
