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
    package/skills/diene-auth-engine-usage/SKILL.md
    package/skills/diene-auth-engine-usage/patterns.md
  )
  missing=0
  for path in "${expected[@]}"; do
    if ! grep -qxF "${path}" <<<"${listing}"; then
      echo "❌ tarball is missing expected path: ${path}" >&2
      missing=1
    fi
  done
  [ "${missing}" -ne 0 ] && exit 1
  if grep -q '^package/fixtures/' <<<"${listing}"; then
    echo "❌ scratch-consumer fixtures must not be packed" >&2
    exit 1
  fi
  usage_skill="$(tar -xOf pkg.tgz package/skills/diene-auth-engine-usage/SKILL.md)"
  if ! grep -qF 'https://github.com/AtomiCloud/diene.bun-auth-engine/blob/main/docs/standards/auth/index.md' <<<"${usage_skill}"; then
    echo "❌ packaged usage skill must point to the repository authentication standard" >&2
    exit 1
  fi
  for contract_text in AppHandoffExpired registerAuthProblems app_handoff_expired; do
    if ! grep -qF "${contract_text}" <<<"${usage_skill}"; then
      echo "❌ packaged usage skill is missing the exact ${contract_text} handoff contract" >&2
      exit 1
    fi
  done
  if grep -q '^package/docs/' <<<"${listing}"; then
    echo "❌ docs/ is outside the package allowlist; use the repository pointer" >&2
    exit 1
  fi
  echo "✅ pack-content: all declared artifacts present"
fi

if [[ ${mode} == "publint" || ${mode} == "all" ]]; then
  echo "🔎 Linting package shape (publint)..."
  ./node_modules/.bin/publint --strict
fi

if [[ ${mode} == "attw" || ${mode} == "all" ]]; then
  echo "🔎 Checking type resolvability (attw)..."
  ./node_modules/.bin/attw pkg.tgz --profile node16
  echo "🔎 Dogfooding the packed tarball in the scratch consumer..."
  ./fixtures/scratch-consumer/validate.sh
fi

echo "✅ Package validation (${mode}) passed"
