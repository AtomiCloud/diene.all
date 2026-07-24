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

echo "📝 Emitting flat type declarations (single shared program)..."
bunx dts-bundle-generator --config dts.config.cjs
cp dist/index.d.ts dist/index.d.cts
cp dist/test-helper.d.ts dist/test-helper.d.cts

echo "🔎 Verifying artifacts..."
for artifact in \
  dist/index.js dist/index.cjs dist/index.d.ts dist/index.d.cts \
  dist/test-helper.js dist/test-helper.cjs dist/test-helper.d.ts dist/test-helper.d.cts; do
  [[ ! -f ${artifact} ]] && echo "❌ build artifact missing: ${artifact}" >&2 && exit 1
done

echo "🏃 Verifying ESM and CJS runtime exports..."
valid_pg='{"MAIN":{"host":"h","port":5432,"database":"d","username":"u","password":"","ssl":false,"pool":{"min":0,"max":10}}}'
node --input-type=module -e "import { postgres, PRESETS } from './dist/index.js'; if (!postgres.safeParse(${valid_pg}).success || PRESETS.postgres !== postgres) process.exit(1)"
node --input-type=module -e "import { InMemoryBlockStorage } from './dist/test-helper.js'; if (typeof InMemoryBlockStorage !== 'function') process.exit(1)"
node -e "const { postgres, PRESETS } = require('./dist/index.cjs'); if (!postgres.safeParse(${valid_pg}).success || PRESETS.postgres !== postgres) process.exit(1)"
node -e "const { InMemoryBlockStorage } = require('./dist/test-helper.cjs'); if (typeof InMemoryBlockStorage !== 'function') process.exit(1)"

echo "✅ Built dist/index.{js,cjs,d.ts,d.cts}, dist/test-helper.{js,cjs,d.ts,d.cts}"
