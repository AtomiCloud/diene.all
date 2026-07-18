#!/usr/bin/env bash
set -euo pipefail

mode="${1:-}"
[ "${mode}" != "unit" ] && [ "${mode}" != "int" ] && echo "❌ Usage: test.sh <unit|int>" >&2 && exit 1

./scripts/ci/setup.sh
./scripts/local/dotnet-test.sh "${mode}" --coverage

echo "✅ ${mode} CI tests complete"
