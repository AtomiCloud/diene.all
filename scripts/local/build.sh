#!/usr/bin/env bash
set -euo pipefail

root_dir="$(git rev-parse --show-toplevel)"
cd "${root_dir}"

echo "🧹 Cleaning dist/..."
rm -rf dist

echo "🔨 Building ESM bundles..."
bun build ./src/index.ts --outfile dist/index.js --format esm --target node --packages external
bun build ./src/build-time.ts --outfile dist/build-time.js --format esm --target node --packages external
bun build ./src/test-helper/index.ts --outfile dist/test-helper.js --format esm --target node --packages external

echo "🔨 Building CommonJS bundles..."
bun build ./src/index.ts --outfile dist/index.cjs --format cjs --target node --packages external
bun build ./src/build-time.ts --outfile dist/build-time.cjs --format cjs --target node --packages external
bun build ./src/test-helper/index.ts --outfile dist/test-helper.cjs --format cjs --target node --packages external

echo "🔠 Typechecking..."
bunx tsc -p tsconfig.json

echo "📝 Emitting flat type declarations (single shared program)..."
bunx dts-bundle-generator --config dts.config.cjs
cp dist/index.d.ts dist/index.d.cts
cp dist/build-time.d.ts dist/build-time.d.cts
cp dist/test-helper.d.ts dist/test-helper.d.cts

echo "🔎 Verifying artifacts..."
for artifact in \
  dist/index.js dist/index.cjs dist/index.d.ts dist/index.d.cts \
  dist/build-time.js dist/build-time.cjs dist/build-time.d.ts dist/build-time.d.cts \
  dist/test-helper.js dist/test-helper.cjs dist/test-helper.d.ts dist/test-helper.d.cts; do
  [[ ! -f ${artifact} ]] && echo "❌ build artifact missing: ${artifact}" >&2 && exit 1
done

echo "🏃 Verifying ESM and CJS runtime exports..."
node --input-type=module -e "import { deepMerge } from './dist/index.js'; if (JSON.stringify(deepMerge({ a: 1 }, { b: 2 })) !== '{\"a\":1,\"b\":2}') process.exit(1)"
node --input-type=module -e "import { buildTimeValueMap } from './dist/build-time.js'; if (buildTimeValueMap({ ATOMI_X: '1', Y: '2' }, 'ATOMI_').ATOMI_X !== '1') process.exit(1)"
node --input-type=module -e "import { InMemoryConfigSource } from './dist/test-helper.js'; if (typeof InMemoryConfigSource !== 'function') process.exit(1)"
node -e "const { deepMerge } = require('./dist/index.cjs'); if (JSON.stringify(deepMerge({ a: 1 }, { b: 2 })) !== '{\"a\":1,\"b\":2}') process.exit(1)"
node -e "const { buildTimeValueMap } = require('./dist/build-time.cjs'); if (buildTimeValueMap({ ATOMI_X: '1', Y: '2' }, 'ATOMI_').ATOMI_X !== '1') process.exit(1)"
node -e "const { InMemoryConfigSource } = require('./dist/test-helper.cjs'); if (typeof InMemoryConfigSource !== 'function') process.exit(1)"

echo "✅ Built dist/index.{js,cjs,d.ts,d.cts}, dist/build-time.{js,cjs,d.ts,d.cts}, dist/test-helper.{js,cjs,d.ts,d.cts}"
