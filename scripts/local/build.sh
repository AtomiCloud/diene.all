#!/usr/bin/env bash
set -euo pipefail

root_dir="$(git rev-parse --show-toplevel)"
cd "${root_dir}"

echo "🧹 Cleaning dist/..."
rm -rf dist

entries=(
  "index:src/index.ts"
  "module:src/entries/module.ts"
  "landscape:src/entries/landscape.ts"
  "content:src/entries/content.ts"
  "content-react:src/entries/content-react.ts"
  "theme:src/entries/theme.ts"
  "theme-react:src/entries/theme-react.ts"
  "discovery:src/entries/discovery.ts"
  "urlstate:src/entries/urlstate.ts"
  "persistence:src/entries/persistence.ts"
  "loader:src/entries/loader.ts"
  "toast:src/entries/toast.ts"
  "a11y:src/entries/a11y.ts"
  "test-helper:src/entries/test-helper.ts"
)

for entry in "${entries[@]}"; do
  name="${entry%%:*}"
  source="${entry#*:}"
  echo "🔨 Building ${name} (ESM + CJS)..."
  bun build "${source}" --outfile "dist/${name}.js" --format esm --target node --packages external
  bun build "${source}" --outfile "dist/${name}.cjs" --format cjs --target node --packages external
done

echo "🔠 Typechecking..."
bunx tsc -p tsconfig.json

echo "📝 Emitting flat type declarations per public entry..."
declaration_pids=()
for entry in "${entries[@]}"; do
  name="${entry%%:*}"
  source="${entry#*:}"
  (
    bunx dts-bundle-generator -o "dist/${name}.d.ts" "${source}" --no-check
    cp "dist/${name}.d.ts" "dist/${name}.d.cts"
  ) &
  declaration_pids+=("$!")
  if [[ ${#declaration_pids[@]} -eq 4 ]]; then
    for declaration_pid in "${declaration_pids[@]}"; do
      wait "$declaration_pid"
    done
    declaration_pids=()
  fi
done
for declaration_pid in "${declaration_pids[@]}"; do
  wait "$declaration_pid"
done

echo "🔎 Verifying artifacts..."
for entry in "${entries[@]}"; do
  name="${entry%%:*}"
  for extension in js cjs d.ts d.cts; do
    artifact="dist/${name}.${extension}"
    [[ ! -f ${artifact} ]] && echo "❌ build artifact missing: ${artifact}" >&2 && exit 1
  done
done

echo "🏃 Verifying ESM and CJS runtime exports..."
node --input-type=module -e "import { createModuleRegistry } from './dist/module.js'; if (createModuleRegistry().has('missing')) process.exit(1)"
node -e "const { createModuleRegistry } = require('./dist/module.cjs'); if (createModuleRegistry().has('missing')) process.exit(1)"
node --input-type=module -e "import * as root from './dist/index.js'; if (Object.keys(root).length !== 10 || typeof root.module.createModuleRegistry !== 'function') process.exit(1)"
node -e "const root = require('./dist/index.cjs'); if (Object.keys(root).length !== 10 || typeof root.module.createModuleRegistry !== 'function') process.exit(1)"

echo "🧱 Verifying React isolation and the NO-DI boundary..."
for name in index module landscape content theme discovery urlstate persistence loader toast a11y; do
  if rg -q "from ['\\\"]react['\\\"]|require\\(['\\\"]react['\\\"]\\)" "dist/${name}.js" "dist/${name}.cjs"; then
    echo "❌ core entry unexpectedly imports React: ${name}" >&2
    exit 1
  fi
done
if rg -n '\b(DIContainer|DependencyContainer|createContainer|wireModules)\b' src/index.ts src/entries src/lib; then
  echo "❌ NO-DI boundary violated by a public container/wiring API" >&2
  exit 1
fi

echo "✅ Built ${#entries[@]} dual-format public entries"
