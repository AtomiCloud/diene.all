#!/usr/bin/env bash
set -euo pipefail

./scripts/local/staticcheck-whole.sh
./scripts/local/deadcode-whole.sh
./scripts/local/staticcheck-production.sh
./scripts/local/deadcode-production.sh
./scripts/local/deadcode-lax.sh

echo "✅ Go deadcode strict pass complete"
