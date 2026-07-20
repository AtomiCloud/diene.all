#!/usr/bin/env bash
set -euo pipefail

go build -trimpath ./...

echo "✅ Go module built"
