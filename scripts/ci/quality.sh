#!/usr/bin/env bash
set -euo pipefail

dart pub publish --dry-run
dart pub global activate pana
pana --no-warning --exit-code-threshold 10 .

echo "✅ pub.dev package quality checks passed"
