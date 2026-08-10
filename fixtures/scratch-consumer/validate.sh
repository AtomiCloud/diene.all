#!/usr/bin/env bash
set -euo pipefail

fixture_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${fixture_dir}/../.." && pwd)"

rm -rf "${fixture_dir}/.runtime"
mkdir -p "${fixture_dir}/.runtime"

if [[ -n ${SCRATCH_REGISTRY_VERSION:-} ]]; then
  echo "📡 Installing published auth-engine ${SCRATCH_REGISTRY_VERSION}..."
  install_dir="${fixture_dir}/.runtime/registry"
  mkdir -p "${install_dir}/src"
  jq --arg spec "${SCRATCH_REGISTRY_VERSION}" \
    '.dependencies["@atomicloud/diene.auth-engine"] = $spec' \
    "${fixture_dir}/package.json" >"${install_dir}/package.json"
  jq -e '.dependencies["@atomicloud/diene.auth-engine"] | startswith("file:")' "${install_dir}/package.json" >/dev/null && echo "❌ registry mode still contains a local file dependency" >&2 && exit 1
  [[ -e "${install_dir}/bun.lock" ]] && echo "❌ registry mode must not inherit the fixture lockfile" >&2 && exit 1
  cp "${fixture_dir}/tsconfig.esm.json" "${fixture_dir}/tsconfig.cjs.json" "${install_dir}/"
  cp "${fixture_dir}/src/esm.ts" "${fixture_dir}/src/cjs.cts" "${install_dir}/src/"
else
  [[ ! -f "${repo_root}/pkg.tgz" ]] && echo "❌ scratch-consumer local-pack mode requires ${repo_root}/pkg.tgz" >&2 && exit 1
  echo "📦 Installing the local packed auth-engine tarball..."
  install_dir="${fixture_dir}"
fi

cd "${install_dir}"
rm -rf "${install_dir}/node_modules"
# A file dependency can retain an older tarball integrity in Bun's lockfile.
# Resolve from the current tarball/registry spec on every isolated proof run.
rm -f "${install_dir}/bun.lock"
bun install --ignore-scripts
"${install_dir}/node_modules/.bin/tsc" -p tsconfig.esm.json
"${install_dir}/node_modules/.bin/tsc" -p tsconfig.cjs.json

echo "🟢 Running Bun ESM assertions..."
bun run src/esm.ts

mkdir -p .runtime
bun build src/esm.ts --outfile .runtime/node-esm.mjs --format esm --target node --packages external
echo "🟢 Running Node ESM assertions..."
node .runtime/node-esm.mjs

bun build src/cjs.cts --outfile .runtime/node-cjs.cjs --format cjs --target node --packages external
echo "🟢 Running Node CJS assertions..."
node .runtime/node-cjs.cjs

echo "✅ scratch consumer typechecks and passes Bun ESM, Node ESM, and Node CJS behavior assertions"
