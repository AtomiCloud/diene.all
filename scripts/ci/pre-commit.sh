#!/usr/bin/env bash
set -euo pipefail

root_dir="$(git rev-parse --show-toplevel)"
cd "${root_dir}"

./scripts/ci/setup.sh
pre-commit run --all-files --show-diff-on-failure

echo "✅ Pre-commit gates passed"
