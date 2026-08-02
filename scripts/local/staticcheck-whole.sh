#!/usr/bin/env bash
set -euo pipefail

echo "🔍 Running whole-repository staticcheck with test analysis"
staticcheck -tests=true ./...

echo "✅ Go staticcheck whole pass complete"
