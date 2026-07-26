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
# Inline the ESM-only Logto SDK in CJS while leaving the other runtime dependencies external.
bun build ./src/index.ts \
  --outfile dist/index.cjs \
  --format cjs \
  --target node \
  --external '@atomicloud/*' \
  --external '@js-temporal/polyfill' \
  --external ioredis \
  --external jose \
  --external zod
bun build ./src/test-helper/index.ts --outfile dist/test-helper.cjs --format cjs --target node --packages external

echo "🔠 Typechecking..."
bunx tsc -p tsconfig.json

echo "📝 Emitting root and TestHelper declarations..."
bunx dts-bundle-generator -o dist/index.d.ts src/index.ts --no-check
cp dist/index.d.ts dist/index.d.cts
bunx tsc -p tsconfig.declarations.json

helper_declarations="dist/.declarations/test-helper"
[[ ! -f ${helper_declarations}/index.d.ts ]] && echo "❌ TestHelper declaration entry is missing: ${helper_declarations}/index.d.ts" >&2 && exit 1

mkdir -p dist/test-helper
while IFS= read -r -d '' source; do
  relative="${source#"${helper_declarations}"/}"
  [[ ${relative} == "index.d.ts" ]] && continue
  esm_target="dist/test-helper/${relative}"
  cjs_target="${esm_target%.d.ts}.d.cts"
  mkdir -p "$(dirname "${esm_target}")"
  sed -E "s#(['\"])\.\./(lib|adapters)/[^'\"]+\1#\1../index.js\1#g" "${source}" >"${esm_target}"
  sed -E "s#\.js(['\"])#.cjs\1#g" "${esm_target}" >"${cjs_target}"
done < <(find "${helper_declarations}" -type f -name '*.d.ts' -print0)

sed -E \
  -e "s#(['\"])\./([^'\"]+)\1#\1./test-helper/\2.js\1#g" \
  -e "s#(['\"])\.\./(lib|adapters)/[^'\"]+\1#\1./index.js\1#g" \
  "${helper_declarations}/index.d.ts" >dist/test-helper.d.ts
sed -E "s#\.js(['\"])#.cjs\1#g" dist/test-helper.d.ts >dist/test-helper.d.cts
rm -rf dist/.declarations

echo "🔎 Verifying artifacts..."
for artifact in \
  dist/index.js dist/index.cjs dist/index.d.ts dist/index.d.cts \
  dist/test-helper.js dist/test-helper.cjs dist/test-helper.d.ts dist/test-helper.d.cts; do
  [[ ! -f ${artifact} ]] && echo "❌ build artifact missing: ${artifact}" >&2 && exit 1
done

echo "🏃 Verifying ESM and CJS runtime exports..."
node --input-type=module -e "import { decodeToken } from './dist/index.js'; const decoded=decodeToken('e30.eyJzdWIiOiJidWlsZC1wcm9vZiJ9.'); if (!(await decoded.isOk())) process.exit(1)"
node --input-type=module -e "import { FakeAuthProvider } from './dist/test-helper.js'; if (typeof FakeAuthProvider !== 'function') process.exit(1)"
node -e "(async()=>{ const { decodeToken }=require('./dist/index.cjs'); if (!(await decodeToken('e30.eyJzdWIiOiJidWlsZC1wcm9vZiJ9.').isOk())) process.exit(1) })().catch(()=>process.exit(1))"
node -e "const { FakeAuthProvider }=require('./dist/test-helper.cjs'); if (typeof FakeAuthProvider !== 'function') process.exit(1)"

./scripts/local/edge-build.sh

echo "✅ Built root and TestHelper ESM, CJS, and declaration artifacts"
