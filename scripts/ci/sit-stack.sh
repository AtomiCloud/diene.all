#!/usr/bin/env bash
set -euo pipefail

mode="${1:-}"
[[ ${mode} != "up" && ${mode} != "down" ]] && echo "❌ usage: $0 <up|down>" >&2 && exit 2
root_dir="$(git rev-parse --show-toplevel)"
cd "${root_dir}"

./scripts/ci/setup.sh
echo "🐳 Applying SIT stack action ${mode}..."
if [[ ${mode} == "up" ]]; then ./scripts/local/up.sh; else ./scripts/local/down.sh; fi
echo "✅ SIT stack action ${mode} completed"
