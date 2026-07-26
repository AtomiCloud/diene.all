#!/usr/bin/env bash
set -euo pipefail

mode="${1:-}"
[ "${mode}" != "unit" ] && [ "${mode}" != "int" ] && [ "${mode}" != "meta" ] && echo "❌ usage: test.sh <unit|int|meta>" >&2 && exit 2

./scripts/ci/setup.sh
./scripts/local/test.sh "${mode}" true false

# The skills-sync/freshness machinery is shell, not Go; exercise its isolated
# behavioral tests once, alongside the unit tier.
if [ "${mode}" = "unit" ]; then
  ./scripts/validate/skills-freshness-test.sh
fi

echo "✅ CI Go ${mode} tests passed"
