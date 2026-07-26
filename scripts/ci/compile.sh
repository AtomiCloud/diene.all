#!/usr/bin/env bash
set -euo pipefail

root_dir="$(git rev-parse --show-toplevel)"
cd "${root_dir}"
artifact="dist/go-consumer"

./scripts/ci/setup.sh
echo "🔨 Compiling the Go consumer binary..."
./scripts/local/build.sh
[ ! -x "${artifact}" ] && echo "❌ Compiled artifact missing: ${artifact}" >&2 && exit 1
echo "✅ Compiled artifact present: ${artifact}"
