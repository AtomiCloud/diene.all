#!/usr/bin/env bash
set -euo pipefail

./scripts/ci/setup.sh
pls typecheck

echo "✅ CI Go typecheck passed"
