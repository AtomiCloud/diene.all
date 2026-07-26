#!/usr/bin/env bash
set -euo pipefail

mode="${1:-}"
[ "${mode}" != "unit" ] && [ "${mode}" != "int" ] && [ "${mode}" != "sit" ] && echo "❌ usage: test.sh <unit|int|sit>" >&2 && exit 2

root_dir="$(git rev-parse --show-toplevel)"
cd "${root_dir}"

./scripts/ci/setup.sh

if [ "${mode}" = "sit" ]; then
  cli_bin="${CLI_BIN:-dist/go-consumer}"
  [ ! -f "${cli_bin}" ] && ./scripts/ci/compile.sh
  [ ! -f "${cli_bin}" ] && echo "❌ SIT binary missing: ${cli_bin}" >&2 && exit 1
  chmod +x "${cli_bin}"
  echo "🧪 Running sit tests against ${cli_bin}..."
  CLI_BIN="${cli_bin}" ./scripts/local/test-sit.sh binary
  echo "✅ CI Go sit tests passed"
  exit 0
fi

./scripts/local/test.sh "${mode}" true false

echo "✅ CI Go ${mode} tests passed"
