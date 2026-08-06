#!/usr/bin/env bash
set -euo pipefail

./scripts/local/deadcode.sh strict

echo "✅ CI Go deadcode gates passed"
