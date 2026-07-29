#!/usr/bin/env bash
set -euo pipefail

root_dir="$(git rev-parse --show-toplevel)"
cd "${root_dir}"

./scripts/validate/chart-contracts.sh
./scripts/validate/problem-catalog.sh
./scripts/validate/release-rails.sh
./scripts/validate/sit-contracts.sh
echo "✅ Release contract validation passed"
