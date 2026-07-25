#!/usr/bin/env bash
set -euo pipefail

./scripts/ci/setup.sh
./scripts/local/vuln.sh

echo "✅ CI Go vulnerability gate passed"
