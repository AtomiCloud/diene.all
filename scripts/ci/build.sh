#!/usr/bin/env bash
set -euo pipefail

./scripts/ci/setup.sh
./scripts/local/build.sh
./scripts/validate/go-consumer-smoke.sh

echo "✅ CI Go build passed"
