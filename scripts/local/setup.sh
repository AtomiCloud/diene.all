#!/usr/bin/env bash
set -euo pipefail

root_dir="$(git rev-parse --show-toplevel)"
cd "${root_dir}"

releaser conventions -c release.yaml
skills-sync sync

echo "📦 Installing dependencies..."
bun install --frozen-lockfile
echo "✅ Dependencies installed"

echo "✅ setup completed"
