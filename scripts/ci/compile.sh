#!/usr/bin/env bash
set -euo pipefail

root_dir="$(git rev-parse --show-toplevel)"
cd "${root_dir}"

./scripts/ci/setup.sh
echo "🔨 Compiling the SIT binary..."
./scripts/local/compile.sh
echo "✅ SIT binary compiled"
