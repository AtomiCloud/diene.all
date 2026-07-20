#!/usr/bin/env bash
set -euo pipefail

root_dir="$(git rev-parse --show-toplevel)"
cd "${root_dir}"

echo "🧹 Cleaning dist/..."
rm -rf dist

echo "🔨 Building ESM bundle..."
bun build ./src/index.ts --outfile dist/index.js --format esm --target node --external ioredis

echo "🔨 Building CommonJS bundle..."
bun build ./src/index.ts --outfile dist/index.cjs --format cjs --target node --external ioredis

echo "🔠 Typechecking..."
bunx tsc -p tsconfig.json

echo "📝 Emitting bundled declarations..."
bunx dts-bundle-generator -o dist/index.d.ts src/index.ts --no-check
cp dist/index.d.ts dist/index.d.cts

echo "🔎 Verifying build artifacts..."
for artifact in dist/index.js dist/index.cjs dist/index.d.ts dist/index.d.cts; do
  [[ ! -f ${artifact} ]] && echo "❌ Build artifact missing: ${artifact}" >&2 && exit 1
done

cmp -s dist/index.d.ts dist/index.d.cts || {
  echo "❌ dist/index.d.cts must be a byte-copy of dist/index.d.ts" >&2
  exit 1
}

node -e 'import("./dist/index.js").then((library) => { if (library.buildSampleKey("Bun Lib", "sample key") !== "bun-lib:sample-key") process.exit(1) })'
node -e 'const library = require("./dist/index.cjs"); if (library.buildSampleKey("Bun Lib", "sample key") !== "bun-lib:sample-key") process.exit(1)'

echo "✅ Built dist/index.{js,cjs,d.ts,d.cts}"
