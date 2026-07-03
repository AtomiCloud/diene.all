#!/usr/bin/env bash
set -euo pipefail
./scripts/ci/setup.sh
pre-commit run --all-files -v
echo "✅ Pre-commit checks passed"
