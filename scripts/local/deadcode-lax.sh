#!/usr/bin/env bash
set -euo pipefail

mkdir -p reports
echo "# Whole repository candidates" >reports/deadcode-llm.txt
staticcheck -tests=true ./... >>reports/deadcode-llm.txt 2>&1 || true
deadcode -test ./... >>reports/deadcode-llm.txt 2>&1 || true
echo "# Production candidates" >>reports/deadcode-llm.txt
staticcheck -tests=false ./... >>reports/deadcode-llm.txt 2>&1 || true
deadcode ./... >>reports/deadcode-llm.txt 2>&1 || true

echo "✅ Go deadcode lax pass complete"
