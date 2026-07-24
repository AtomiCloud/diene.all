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
  entry_names=(
    index module landscape content content-react theme theme-react discovery
    urlstate persistence loader toast a11y test-helper
  )
  expected=(
    package/skills/diene-frontend-utils-usage/SKILL.md
    package/skills/diene-frontend-utils-usage/agents/openai.yaml
    package/skills/diene-frontend-utils-usage/assets/consumer.ts
    package/skills/diene-frontend-utils-usage/assets/consumer-test.ts
  )
  for name in "${entry_names[@]}"; do
    expected+=(
      "package/dist/${name}.js"
      "package/dist/${name}.cjs"
      "package/dist/${name}.d.ts"
      "package/dist/${name}.d.cts"
    )
  done
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
  # Node 10 predates package.json subpath exports. Profile Node 16 so attw
  # checks the supported CJS, ESM, and bundler resolvers without false-failing
  # every focused entry on an end-of-life resolver.
  ./node_modules/.bin/attw pkg.tgz --profile node16
fi

echo "✅ Package validation (${mode}) passed"
