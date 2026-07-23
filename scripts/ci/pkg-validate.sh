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

run_content() {
  echo "🔎 Verifying tarball contents (pack-content)..."
  local listing expected missing
  listing="$(tar -tzf pkg.tgz)"
  expected=(
    package/dist/index.js
    package/dist/index.cjs
    package/dist/index.d.ts
    package/dist/index.d.cts
    package/skills/diene-bun-lib-usage/SKILL.md
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
}

run_publint() {
  echo "🔎 Linting package shape (publint)..."
  ./node_modules/.bin/publint --strict
}

run_attw() {
  echo "🔎 Checking type resolvability (attw)..."
  ./node_modules/.bin/attw pkg.tgz
}

case "${mode}" in
content) run_content ;;
publint) run_publint ;;
attw) run_attw ;;
all)
  run_content
  run_publint
  run_attw
  ;;
esac

echo "✅ Package validation (${mode}) passed"
