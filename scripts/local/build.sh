#!/usr/bin/env bash
set -euo pipefail

root_dir="$(git rev-parse --show-toplevel)"
cd "${root_dir}"

echo "🧹 Cleaning dist/..."
rm -rf dist

echo "🔨 Building ESM bundles..."
bun build ./src/index.ts --outfile dist/index.js --format esm --target node --packages external
bun build ./src/test-helper/index.ts --outfile dist/test-helper.js --format esm --target node --packages external

echo "🔨 Building CommonJS bundles..."
bun build ./src/index.ts --outfile dist/index.cjs --format cjs --target node --packages external
bun build ./src/test-helper/index.ts --outfile dist/test-helper.cjs --format cjs --target node --packages external

echo "🔠 Typechecking..."
bunx tsc -p tsconfig.json

echo "📝 Emitting bundled declarations..."
bunx dts-bundle-generator -o dist/index.d.ts src/index.ts --no-check
cp dist/index.d.ts dist/index.d.cts
bunx dts-bundle-generator -o dist/test-helper.d.ts src/test-helper/index.ts --no-check
cp dist/test-helper.d.ts dist/test-helper.d.cts

echo "🔎 Verifying build artifacts..."
for artifact in \
  dist/index.js dist/index.cjs dist/index.d.ts dist/index.d.cts \
  dist/test-helper.js dist/test-helper.cjs dist/test-helper.d.ts dist/test-helper.d.cts; do
  [[ ! -f ${artifact} ]] && echo "❌ Build artifact missing: ${artifact}" >&2 && exit 1
done

cmp -s dist/index.d.ts dist/index.d.cts || {
  echo "❌ dist/index.d.cts must be a byte-copy of dist/index.d.ts" >&2
  exit 1
}
cmp -s dist/test-helper.d.ts dist/test-helper.d.cts || {
  echo "❌ dist/test-helper.d.cts must be a byte-copy of dist/test-helper.d.ts" >&2
  exit 1
}

node --input-type=module -e "import { Ok } from './dist/index.js'; if (await Ok(1).map((value) => value + 1).unwrap() !== 2) process.exit(1)"
node -e 'const { Ok } = require("./dist/index.cjs"); Ok(1).map((value) => value + 1).unwrap().then((value) => { if (value !== 2) process.exit(1) }).catch(() => process.exit(1))'
node -e 'const { Ok } = require("./dist/index.cjs"); const { expectOk } = require("./dist/test-helper.cjs"); expectOk(Ok(1)).then((value) => { if (value !== 1) process.exit(1) }).catch(() => process.exit(1))'

echo "✅ Built dist/index.{js,cjs,d.ts,d.cts} and dist/test-helper.{js,cjs,d.ts,d.cts}"
