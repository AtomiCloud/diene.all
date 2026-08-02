#!/usr/bin/env bash
set -euo pipefail

mode="${1:-}"
[ "${mode}" != "unit" ] && [ "${mode}" != "int" ] && [ "${mode}" != "meta" ] && echo "❌ Usage: test.sh <unit|int|meta>" >&2 && exit 1

./scripts/ci/setup.sh
./scripts/local/dotnet-test.sh "${mode}" --coverage

echo "✅ ${mode} CI tests complete"
