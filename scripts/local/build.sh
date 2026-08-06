#!/usr/bin/env bash
set -euo pipefail

mkdir -p dist
go build -trimpath -o dist/go-base ./cmd/go-base

echo "✅ Go binary built"
