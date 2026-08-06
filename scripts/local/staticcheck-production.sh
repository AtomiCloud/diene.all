#!/usr/bin/env bash
set -euo pipefail

echo "🔍 Running production staticcheck without test analysis"
staticcheck -tests=false ./...

echo "✅ Go staticcheck production pass complete"
