#!/usr/bin/env bash
set -euo pipefail

root_dir="$(git rev-parse --show-toplevel)"
cd "${root_dir}"

echo "🧹 Cleaning dist/..."
rm -rf dist

echo "🔨 Building ESM bundles..."
bun build ./src/index.ts --outfile dist/index.js --format esm --target node --packages external
bun build ./src/test-helper/index.ts --outfile dist/test-helper.js --format esm --target node --packages external

echo "🔨 Building CJS bundles..."
bun build ./src/index.ts --outfile dist/index.cjs --format cjs --target node --packages external
bun build ./src/test-helper/index.ts --outfile dist/test-helper.cjs --format cjs --target node --packages external

echo "🔠 Typechecking..."
bunx tsc -p tsconfig.json

echo "📝 Emitting ESM and CommonJS declarations..."
bunx tsc -p tsconfig.declarations.json
for source in dist/lib/*.d.ts; do
  target="${source%.d.ts}.d.cts"
  sed "s/\\.js'/\\.cjs'/g" "${source}" >"${target}"
done
sed "s/\\.js'/\\.cjs'/g" dist/index.d.ts >dist/index.d.cts
sed -e "s#'../lib/#'./lib/#g" \
  dist/test-helper/index.d.ts >dist/test-helper.d.ts
sed -e "s#'../lib/#'./lib/#g" -e "s/\\.js'/\\.cjs'/g" \
  dist/test-helper/index.d.ts >dist/test-helper.d.cts
rm -rf dist/test-helper

echo "🔎 Verifying artifacts..."
for artifact in \
  dist/index.js dist/index.cjs dist/index.d.ts dist/index.d.cts \
  dist/test-helper.js dist/test-helper.cjs dist/test-helper.d.ts dist/test-helper.d.cts; do
  [[ ! -f ${artifact} ]] && echo "❌ build artifact missing: ${artifact}" >&2 && exit 1
done

echo "🏃 Verifying ESM and CJS runtime exports..."
node --input-type=module -e "import { buildProblemTypeUri } from './dist/index.js'; if (!buildProblemTypeUri({scheme:'https',host:'errors.example',landscape:'pichu',platform:'nitroso',service:'zinc',module:'api'},'v1','validation_error').endsWith('/v1/validation_error')) process.exit(1)"
node --input-type=module -e "import { createGenericProblemRegistry } from './dist/index.js'; import { buildProblemFromRegistry } from './dist/test-helper.js'; const registry=createGenericProblemRegistry({scheme:'https',host:'errors.example',landscape:'pichu',platform:'nitroso',service:'zinc',module:'api'}); if (buildProblemFromRegistry(registry,'unauthorized',{data:{}}).status !== 401) process.exit(1)"
node -e "const { buildProblemTypeUri } = require('./dist/index.cjs'); if (!buildProblemTypeUri({scheme:'https',host:'errors.example',landscape:'pichu',platform:'nitroso',service:'zinc',module:'api'},'v1','validation_error').endsWith('/v1/validation_error')) process.exit(1)"
node -e "const { createGenericProblemRegistry } = require('./dist/index.cjs'); const { buildProblemFromRegistry } = require('./dist/test-helper.cjs'); const registry=createGenericProblemRegistry({scheme:'https',host:'errors.example',landscape:'pichu',platform:'nitroso',service:'zinc',module:'api'}); if (buildProblemFromRegistry(registry,'unauthorized',{data:{}}).status !== 401) process.exit(1)"
bunx tsc -p fixtures/package-consumer/tsconfig.json

echo "✅ Built root and TestHelper ESM, CJS, and declaration artifacts"
