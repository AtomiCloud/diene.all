#!/usr/bin/env bash
set -euo pipefail

root_dir="$(git rev-parse --show-toplevel)"
cd "${root_dir}"

mode="${1:-all}"
case "${mode}" in
content | publint | attw | all) ;;
*)
  echo "❌ mode must be 'content', 'publint', 'attw', or 'all'" >&2
  exit 1
  ;;
esac

./scripts/ci/build.sh

echo "📦 Packing tarball..."
bun pm pack --filename pkg.tgz

if [[ ${mode} == "content" || ${mode} == "all" ]]; then
  echo "🔎 Verifying tarball contents (pack-content)..."
  listing="$(tar -tzf pkg.tgz)"
  expected=(
    package/dist/index.js
    package/dist/index.cjs
    package/dist/index.d.ts
    package/dist/index.d.cts
    package/dist/test-helper.js
    package/dist/test-helper.cjs
    package/dist/test-helper.d.ts
    package/dist/test-helper.d.cts
    package/skills/diene-result-usage/SKILL.md
    package/skills/diene-result-usage/assets/consumer.ts
    package/skills/diene-result-usage/assets/consumer.cjs
    package/skills/diene-result-usage/assets/test-helper.md
  )
  missing=0
  for path in "${expected[@]}"; do
    if ! grep -qxF "${path}" <<<"${listing}"; then
      echo "❌ tarball is missing expected path: ${path}" >&2
      missing=1
    fi
  done
  [ "${missing}" -ne 0 ] && exit 1
  echo "✅ pack-content: all declared artifacts present"
fi

if [[ ${mode} == "publint" || ${mode} == "all" ]]; then
  echo "🔎 Linting package shape (publint)..."
  ./node_modules/.bin/publint --strict
fi

if [[ ${mode} == "attw" || ${mode} == "all" ]]; then
  echo "🔎 Checking type resolvability (attw)..."
  ./node_modules/.bin/attw pkg.tgz --profile node16
  echo "🔎 Checking root and TestHelper type identity..."
  ./node_modules/.bin/tsc -p fixtures/package-consumer/tsconfig.json
fi

echo "✅ Package validation (${mode}) passed"
