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
  echo "🔎 Verifying complete tarball inventory..."
  listing="$(tar -tzf pkg.tgz)"
  entries=(
    index test-helper result result-test-helper interfaces interfaces-test-helper
    core-utils config config-test-helper problems problems-test-helper otel
    otel-test-helper auth auth-test-helper api api-test-helper standard-config
    standard-config-test-helper frontend-utils frontend-utils-test-helper
  )
  expected=(
    package/skills/diene-e2e-usage/SKILL.md
    package/docs/standards/e2e/index.md
  )
  for entry in "${entries[@]}"; do
    expected+=(
      "package/dist/${entry}.js"
      "package/dist/${entry}.cjs"
      "package/dist/${entry}.d.ts"
      "package/dist/${entry}.d.cts"
    )
  done
  missing=0
  for path in "${expected[@]}"; do
    if ! rg -qxF "${path}" <<<"${listing}"; then
      echo "❌ tarball is missing expected path: ${path}" >&2
      missing=1
    fi
  done
  if rg -q '^package/vendor/' <<<"${listing}"; then
    echo "❌ vendor bridge must never be published" >&2
    missing=1
  fi
  [[ ${missing} -eq 0 ]] || exit 1
  echo "✅ pack-content: complete entry/docs/skill inventory present; vendor absent"
fi

if [[ ${mode} == "publint" || ${mode} == "all" ]]; then
  echo "🔎 Linting package shape (publint)..."
  ./node_modules/.bin/publint --strict
fi

if [[ ${mode} == "attw" || ${mode} == "all" ]]; then
  echo "🔎 Checking all export conditions (attw)..."
  ./node_modules/.bin/attw pkg.tgz --profile node16
fi

echo "✅ Package validation (${mode}) passed"
