#!/usr/bin/env bash
set -euo pipefail

mkdir -p dist
go build -trimpath -o dist/manager ./cmd/manager

echo "✅ Go binary built"
