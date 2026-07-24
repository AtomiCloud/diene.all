#!/usr/bin/env bash
set -euo pipefail

root_dir="$(git rev-parse --show-toplevel)"
cd "${root_dir}"

echo "🧹 Cleaning dist/..."
rm -rf dist

echo "🔨 Building ESM bundle..."
bun build ./src/index.ts --outfile dist/index.js --format esm --target node --packages external
bun build ./src/test-helper/index.ts --outfile dist/test-helper.js --format esm --target node --packages external

echo "🔨 Building CJS bundle..."
bun build ./src/index.ts --outfile dist/index.cjs --format cjs --target node --packages external
bun build ./src/test-helper/index.ts --outfile dist/test-helper.cjs --format cjs --target node --packages external

echo "🔠 Typechecking..."
bunx tsc -p tsconfig.json

echo "📝 Emitting flat type declarations..."
bunx dts-bundle-generator -o dist/index.d.ts src/index.ts --no-check
cp dist/index.d.ts dist/index.d.cts
bunx dts-bundle-generator -o dist/test-helper.d.ts src/test-helper/index.ts --no-check
cp dist/test-helper.d.ts dist/test-helper.d.cts

echo "🔎 Verifying artifacts..."
for artifact in \
  dist/index.js dist/index.cjs dist/index.d.ts dist/index.d.cts \
  dist/test-helper.js dist/test-helper.cjs dist/test-helper.d.ts dist/test-helper.d.cts; do
  [[ ! -f ${artifact} ]] && echo "❌ build artifact missing: ${artifact}" >&2 && exit 1
done

echo "🏃 Verifying ESM and CJS runtime exports..."
node --input-type=module -e "import * as api from './dist/index.js'; if (api.API_PROBLEM_VERSION !== 'v1' || typeof api.toResult !== 'function' || typeof api.apiEngineConfigBlockSchema?.safeParse !== 'function') process.exit(1)"
node -e "const api = require('./dist/index.cjs'); if (api.API_PROBLEM_VERSION !== 'v1' || typeof api.toResult !== 'function' || typeof api.apiEngineConfigBlockSchema?.safeParse !== 'function') process.exit(1)"
node --input-type=module -e "import { testPortal } from './dist/test-helper.js'; if (testPortal.module !== 'tests') process.exit(1)"
node -e "const { testPortal } = require('./dist/test-helper.cjs'); if (testPortal.module !== 'tests') process.exit(1)"

echo "✅ Built root and test-helper ESM, CJS, and declaration artifacts"
