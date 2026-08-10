#!/usr/bin/env bash
set -euo pipefail

./scripts/local/typecheck.sh

echo "✅ CI Go typecheck passed"
