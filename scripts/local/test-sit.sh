#!/usr/bin/env bash
set -euo pipefail

mode="${1:-binary}"
[[ ${mode} != "binary" && ${mode} != "coverage" ]] && echo "❌ usage: $0 <binary|coverage>" >&2 && exit 2
root_dir="$(git rev-parse --show-toplevel)"
cd "${root_dir}"

if [[ ${mode} == "binary" ]]; then
  ./scripts/local/compile.sh
  echo "🧪 Running black-box SIT journeys..."
  SIT_DRIVER=binary CLI_BIN=dist/bin/bun-consumer bun test --config=bunfig.sit.toml
else
  echo "🧪 Running in-process SIT coverage journeys..."
  rm -rf coverage/sit
  SIT_DRIVER=inprocess bun test --config=bunfig.sit.toml --coverage
  [[ ! -f coverage/sit/lcov.info ]] && echo "❌ SIT coverage artifact missing" >&2 && exit 1
fi
echo "✅ SIT journeys passed"
