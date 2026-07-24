#!/usr/bin/env bash
set -euo pipefail

root_dir="$(git rev-parse --show-toplevel)"
cd "${root_dir}"

echo "📦 Installing dependencies..."
install_args=(--frozen-lockfile)
[[ ${BUN_INSTALL_OFFLINE:-0} == "1" ]] && install_args+=(--offline)
bun install "${install_args[@]}"
echo "✅ Dependencies installed"
