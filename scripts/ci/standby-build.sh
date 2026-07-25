#!/usr/bin/env bash
set -euo pipefail

# Web standby rail (ARCHITECTURE §4 CF-outage posture): every release
# dual-deploys — Workers via CloudflareDeploy version pinning PLUS a standby
# Next.js build deployable to Vercel/any Node host behind a pre-provisioned,
# repointable CNAME. This job produces and validates the standby artifact.

./scripts/ci/setup.sh

PATH="$(pwd)/node_modules/.bin:${PATH}"
export PATH

echo "🔧 Building the standalone standby artifact..."
next build

[[ -f .next/standalone/server.js ]] || {
  echo "❌ standby artifact missing .next/standalone/server.js" >&2
  exit 1
}

echo "✅ Standby build artifact validated (.next/standalone)"
