#!/usr/bin/env bash
set -euo pipefail

./scripts/ci/setup.sh
./scripts/local/dotnet-dead-code.sh --strict

echo "✅ CI dead-code inspection complete"
