#!/usr/bin/env bash
set -euo pipefail

# Extended binary inventory for this node's own toolchain.
#
# scripts/validate/binary-smoke.sh covers the inherited repository binaries. The
# Next.js train adds four of its own — three that arrive through node_modules
# rather than the Nix shell, plus the i18n linter — and every one of them is
# load-bearing for a rail that only runs late (upload, e2e, SIT). A `--version`
# is not much, but "the binary resolves and answers" is exactly the failure this
# catches: a dependency dropped from package.json looks fine until CD reaches
# for it.

./scripts/local/setup.sh
export PATH="${PWD}/node_modules/.bin:${PATH}"

binaries=(wrangler bru playwright)
for binary in "${binaries[@]}"; do
  command -v "${binary}" >/dev/null || {
    echo "❌ binary '${binary}' is missing from node_modules/.bin" >&2
    exit 1
  }
done

echo "🔎 wrangler..."
wrangler --version >/dev/null

echo "🔎 opennextjs-cloudflare..."
# The adapter ships no --version, so its help output is the smoke.
bunx opennextjs-cloudflare --help >/dev/null

echo "🔎 bru..."
bru --version >/dev/null

echo "🔎 playwright..."
playwright --version >/dev/null

echo "🔎 i18n key linter..."
bun scripts/validate/i18n-keys.ts >/dev/null

echo "✅ Extended binary inventory green"
