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
bunx tsc -p tsconfig.declarations.json
# The helper references the root and sibling packages by name, so a single emitted
# declaration resolves correctly under both the import (.d.ts) and require (.d.cts)
# conditions — no per-format specifier rewrite is required.
cp dist/.declarations/test-helper/index.d.ts dist/test-helper.d.ts
cp dist/.declarations/test-helper/index.d.ts dist/test-helper.d.cts
rm -rf dist/.declarations

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

echo "🔎 Verifying the root bundle does not self-import the otel package..."
if grep -qF "@atomicloud/diene.otel" dist/index.js; then
  echo "❌ dist/index.js must not self-import the otel package" >&2
  exit 1
fi

echo "🏃 Verifying ESM and CJS runtime exports (canonical block round-trips through the schema)..."
node --input-type=module -e "import { otelBlockSchema, defaultOtelBlock } from './dist/index.js'; const parsed = otelBlockSchema.parse(defaultOtelBlock); if (!parsed.logs.enabled || parsed.traces.sampler.ratio !== 1) process.exit(1)"
node -e "const { otelBlockSchema, defaultOtelBlock } = require('./dist/index.cjs'); const parsed = otelBlockSchema.parse(defaultOtelBlock); if (!parsed.logs.enabled || parsed.traces.sampler.ratio !== 1) process.exit(1)"

echo "🏃 Verifying the telemetry test double loads under ESM and CJS..."
node --input-type=module -e "import { InMemoryTraceEmitter } from './dist/test-helper.js'; if (typeof InMemoryTraceEmitter !== 'function') process.exit(1)"
node -e "const { InMemoryTraceEmitter } = require('./dist/test-helper.cjs'); if (typeof InMemoryTraceEmitter !== 'function') process.exit(1)"

echo "🔎 Verifying Node16 consumer type resolution..."
bunx tsc -p fixtures/package-consumer/tsconfig.json

echo "✅ Built dist/index.{js,cjs,d.ts,d.cts} and dist/test-helper.{js,cjs,d.ts,d.cts}"
