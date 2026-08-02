#!/usr/bin/env bash
set -euo pipefail

./scripts/ci/setup.sh
./scripts/local/typecheck.sh

echo "✅ CI Go typecheck passed"
