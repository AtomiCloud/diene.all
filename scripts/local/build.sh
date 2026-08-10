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
# The helper references the root and result packages by name, so a single emitted
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

echo "🔎 Verifying the helper externalizes the root package (no PortError duplication)..."
grep -qF "@atomicloud/diene.interfaces" dist/test-helper.js || {
  echo "❌ dist/test-helper.js must import the root package by name, not inline it" >&2
  exit 1
}
grep -qF "@atomicloud/diene.interfaces" dist/test-helper.cjs || {
  echo "❌ dist/test-helper.cjs must require the root package by name, not inline it" >&2
  exit 1
}
grep -qF "@atomicloud/diene.interfaces" dist/test-helper.d.ts || {
  echo "❌ dist/test-helper.d.ts must reference the root package types, not re-declare them" >&2
  exit 1
}
if grep -qF "@atomicloud/diene.interfaces" dist/index.js; then
  echo "❌ dist/index.js must not self-import the interfaces package" >&2
  exit 1
fi

echo "🏃 Verifying ESM and CJS runtime exports and shared PortError identity..."
node --input-type=module -e "import { PortError, portError } from './dist/index.js'; const e = portError('vfs', 'not-found', 'readFile', 'missing'); if (!(e instanceof PortError) || e.port !== 'vfs' || e._tag !== 'PortError') process.exit(1)"
node -e "const { PortError, portError } = require('./dist/index.cjs'); const e = portError('vfs', 'not-found', 'readFile', 'missing'); if (!(e instanceof PortError) || e.port !== 'vfs' || e._tag !== 'PortError') process.exit(1)"
node --input-type=module -e "import { PortError } from './dist/index.js'; import { InMemoryTerminal } from './dist/test-helper.js'; const t = new InMemoryTerminal(); t.close(); const err = await t.write({ channel: 'stdout', text: 'x' }).unwrapErr(); if (!(err instanceof PortError) || err.code !== 'closed') process.exit(1)"
node -e "const { PortError } = require('./dist/index.cjs'); const { InMemoryTerminal } = require('./dist/test-helper.cjs'); const t = new InMemoryTerminal(); t.close(); t.write({ channel: 'stdout', text: 'x' }).unwrapErr().then((err) => { if (!(err instanceof PortError) || err.code !== 'closed') process.exit(1) }).catch(() => process.exit(1))"
node --input-type=module -e "import { createRequire } from 'node:module'; import { PortError } from './dist/index.js'; const require = createRequire(import.meta.url); const { InMemoryTerminal } = require('./dist/test-helper.cjs'); const t = new InMemoryTerminal(); t.close(); const err = await t.write({ channel: 'stdout', text: 'x' }).unwrapErr(); if (!(err instanceof PortError) || err.code !== 'closed') process.exit(1)"
node -e "const { PortError } = require('./dist/index.cjs'); import('./dist/test-helper.js').then(async ({ InMemoryTerminal }) => { const t = new InMemoryTerminal(); t.close(); const err = await t.write({ channel: 'stdout', text: 'x' }).unwrapErr(); if (!(err instanceof PortError) || err.code !== 'closed') process.exit(1) }).catch(() => process.exit(1))"

echo "🔎 Verifying Node16 consumer type resolution..."
bunx tsc -p fixtures/package-consumer/tsconfig.json

echo "✅ Built dist/index.{js,cjs,d.ts,d.cts} and dist/test-helper.{js,cjs,d.ts,d.cts}"
