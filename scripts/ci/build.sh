#!/usr/bin/env bash
set -euo pipefail

root_dir="$(git rev-parse --show-toplevel)"
cd "${root_dir}"

./scripts/ci/setup.sh
./scripts/local/build.sh

echo "✅ CI Go build passed"
