#!/usr/bin/env bash
set -euo pipefail

./scripts/ci/setup.sh
./scripts/local/build.sh
./scripts/local/test.sh sit false false

echo "✅ Go system integration tests passed"
