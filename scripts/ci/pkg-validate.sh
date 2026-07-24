#!/usr/bin/env bash
set -euo pipefail

./scripts/ci/setup.sh
./scripts/local/build.sh

archive="pkg.tgz"
rm -f "${archive}"

echo "📦 Packing library..."
bun pm pack --filename "${archive}"

echo "🔎 Validating packed content..."
./scripts/validate/bun-package.sh pack-content "${archive}"

echo "🔎 Validating package metadata..."
./scripts/validate/bun-package.sh metadata "${archive}"

echo "🔎 Running publint strict..."
./scripts/validate/bun-package.sh publint "${archive}"

echo "🔎 Running Are The Types Wrong..."
./scripts/validate/bun-package.sh attw "${archive}"

echo "✅ Packed library validation passed"
