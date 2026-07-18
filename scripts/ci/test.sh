#!/usr/bin/env bash
set -euo pipefail

mode="${1:-}"
[ -z "${mode}" ] && echo "❌ test mode not set" >&2 && exit 1

./scripts/ci/setup.sh
./scripts/local/test.sh "${mode}" true false

echo "✅ CI Go ${mode} tests passed"
