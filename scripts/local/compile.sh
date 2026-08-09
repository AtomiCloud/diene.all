#!/usr/bin/env bash
set -euo pipefail

root_dir="$(git rev-parse --show-toplevel)"
cd "${root_dir}"
artifact="dist/bin/bun-consumer"

echo "🔨 Compiling the Bun consumer binary..."
mkdir -p "$(dirname "${artifact}")"
bun build --compile ./src/index.ts --outfile "${artifact}"
[[ ! -x ${artifact} ]] && echo "❌ Compiled artifact missing: ${artifact}" >&2 && exit 1
echo "✅ Compiled artifact present: ${artifact}"
