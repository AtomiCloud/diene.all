#!/usr/bin/env bash
set -euo pipefail

root_dir="$(git rev-parse --show-toplevel)"
cd "${root_dir}"

entries=(
  "index:src/index.ts"
  "test-helper:src/test-helper/index.ts"
  "result:src/entries/result.ts"
  "result-test-helper:src/entries/result-test-helper.ts"
  "interfaces:src/entries/interfaces.ts"
  "interfaces-test-helper:src/entries/interfaces-test-helper.ts"
  "core-utils:src/entries/core-utils.ts"
  "config:src/entries/config.ts"
  "config-test-helper:src/entries/config-test-helper.ts"
  "problems:src/entries/problems.ts"
  "problems-test-helper:src/entries/problems-test-helper.ts"
  "otel:src/entries/otel.ts"
  "otel-test-helper:src/entries/otel-test-helper.ts"
  "auth:src/entries/auth.ts"
  "auth-test-helper:src/entries/auth-test-helper.ts"
  "api:src/entries/api.ts"
  "api-test-helper:src/entries/api-test-helper.ts"
  "standard-config:src/entries/standard-config.ts"
  "standard-config-test-helper:src/entries/standard-config-test-helper.ts"
  "frontend-utils:src/entries/frontend-utils.ts"
  "frontend-utils-test-helper:src/entries/frontend-utils-test-helper.ts"
)

echo "🧹 Cleaning dist/..."
rm -rf dist

for entry in "${entries[@]}"; do
  name="${entry%%:*}"
  source="${entry#*:}"
  echo "🔨 Building ${name} (ESM + CJS)..."
  bun build "${source}" --outfile "dist/${name}.js" --format esm --target node --packages external
  bun build "${source}" --outfile "dist/${name}.cjs" --format cjs --target node --packages external
done

echo "🔠 Typechecking..."
bunx tsc -p tsconfig.json

echo "📝 Emitting all declarations in one TypeScript program..."
bunx tsc -p tsconfig.declarations.json

cp dist/.declarations/index.d.ts dist/index.d.ts
cp dist/index.d.ts dist/index.d.cts
cp dist/.declarations/test-helper/index.d.ts dist/test-helper.d.ts
sed -e "s#'./bruno.js'#'./bruno.cjs'#" -e "s#'./garden.js'#'./garden.cjs'#" \
  dist/test-helper.d.ts >dist/test-helper.d.cts
for helper_source in bruno garden; do
  cp "dist/.declarations/test-helper/${helper_source}.d.ts" "dist/${helper_source}.d.ts"
  cp "dist/${helper_source}.d.ts" "dist/${helper_source}.d.cts"
done

for entry in "${entries[@]:2}"; do
  name="${entry%%:*}"
  source="${entry#*:}"
  source="${source#src/}"
  declaration="dist/.declarations/${source%.ts}.d.ts"
  cp "${declaration}" "dist/${name}.d.ts"
  cp "dist/${name}.d.ts" "dist/${name}.d.cts"
done
rm -rf dist/.declarations

echo "🔎 Verifying all artifacts and runtime entries..."
for entry in "${entries[@]}"; do
  name="${entry%%:*}"
  for extension in js cjs d.ts d.cts; do
    artifact="dist/${name}.${extension}"
    [[ -f ${artifact} ]] || {
      echo "❌ build artifact missing: ${artifact}" >&2
      exit 1
    }
  done
  node --input-type=module -e "const entry = await import('./dist/${name}.js'); if (Object.keys(entry).length === 0) process.exit(1)"
  node -e "const entry = require('./dist/${name}.cjs'); if (Object.keys(entry).length === 0) process.exit(1)"
done
for artifact in dist/bruno.d.ts dist/bruno.d.cts dist/garden.d.ts dist/garden.d.cts; do
  [[ -f ${artifact} ]] || {
    echo "❌ internal helper declaration missing: ${artifact}" >&2
    exit 1
  }
done

echo "🔒 Verifying root/helper import gate and curated identities..."
if rg -q "test-helper|testcontainers" dist/index.js dist/index.cjs; then
  echo "❌ root bundle reaches helper-only code" >&2
  exit 1
fi
node --input-type=module -e "import { Ok, result } from './dist/index.js'; if (!Object.isFrozen(result) || result.Ok !== Ok) process.exit(1)"
node -e "const { Ok, result } = require('./dist/index.cjs'); if (!Object.isFrozen(result) || result.Ok !== Ok) process.exit(1)"
node --input-type=module -e "import { createBrunoEnvironment } from './dist/test-helper.js'; if (createBrunoEnvironment({ baseUrl: 'https://api.test' }).baseUrl !== 'https://api.test') process.exit(1)"
node -e "const { createBrunoEnvironment } = require('./dist/test-helper.cjs'); if (createBrunoEnvironment({ baseUrl: 'https://api.test' }).baseUrl !== 'https://api.test') process.exit(1)"
node scripts/local/verify-built-exports.mjs

echo "✅ Built ${#entries[@]} dual-format public entries with declarations"
