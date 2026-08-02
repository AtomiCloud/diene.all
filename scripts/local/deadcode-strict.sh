#!/usr/bin/env bash
set -euo pipefail

./scripts/local/deadcode-whole.sh
./scripts/local/deadcode-production.sh
./scripts/local/deadcode-lax.sh

echo "✅ Go deadcode strict pass complete"
