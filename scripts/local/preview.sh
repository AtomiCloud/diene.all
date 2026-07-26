#!/usr/bin/env bash
set -euo pipefail

root_dir="$(git rev-parse --show-toplevel)"
cd "${root_dir}"
artifact="./dist/go-consumer"

./scripts/local/build.sh
echo "🔎 Running the compiled Go consumer artifact ${artifact}..."
./scripts/local/with-dev-env.sh "${artifact}" "$@"
echo "✅ Compiled Go consumer run completed"
