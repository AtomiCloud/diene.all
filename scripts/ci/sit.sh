#!/usr/bin/env bash
set -euo pipefail

./scripts/ci/setup.sh
pls test:sit

echo "✅ Go system integration tests passed"
