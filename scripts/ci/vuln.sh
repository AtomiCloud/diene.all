#!/usr/bin/env bash
set -euo pipefail

root_dir="$(git rev-parse --show-toplevel)"
cd "${root_dir}"

./scripts/local/vuln.sh

echo "✅ CI Go vulnerability gate passed"
