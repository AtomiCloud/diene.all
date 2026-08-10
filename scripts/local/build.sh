#!/usr/bin/env bash
set -euo pipefail

root_dir="$(git rev-parse --show-toplevel)"
cd "${root_dir}"

echo "🧹 Cleaning dist/..."
rm -rf dist

echo "🔨 Building ESM bundle..."
bun build ./src/index.ts --outfile dist/index.js --format esm --target node --packages external

echo "🔨 Building CJS bundle..."
bun build ./src/index.ts --outfile dist/index.cjs --format cjs --target node --packages external

echo "🔠 Typechecking..."
bunx tsc -p tsconfig.json

echo "📝 Emitting flat type declarations..."
bunx dts-bundle-generator -o dist/index.d.ts src/index.ts --no-check
cp dist/index.d.ts dist/index.d.cts

echo "🔎 Verifying artifacts..."
for artifact in dist/index.js dist/index.cjs dist/index.d.ts dist/index.d.cts; do
  [[ ! -f ${artifact} ]] && echo "❌ build artifact missing: ${artifact}" >&2 && exit 1
done

echo "🏃 Verifying ESM and CJS runtime exports..."
node --input-type=module -e "import { namespacedKey, slugify } from './dist/index.js'; if (slugify('Build Proof') !== 'build-proof') process.exit(1); const result = namespacedKey('Build Proof', 'ESM'); if (!(await result.isOk()) || (await result.unwrap()) !== 'build-proof:esm') process.exit(1)"
node -e "const { namespacedKey, slugify } = require('./dist/index.cjs'); if (slugify('Build Proof') !== 'build-proof') process.exit(1); namespacedKey('Build Proof', 'CJS').unwrap().then((value) => { if (value !== 'build-proof:cjs') process.exit(1) }).catch(() => process.exit(1))"

echo "✅ Built dist/index.{js,cjs,d.ts,d.cts}"
