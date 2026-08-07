#!/usr/bin/env bash
set -euo pipefail

pre-commit run --all-files --show-diff-on-failure

echo "✅ Pre-commit gates passed"
