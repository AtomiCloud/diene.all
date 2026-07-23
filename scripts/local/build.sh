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

echo "✅ Built dist/index.{js,cjs,d.ts,d.cts}"
