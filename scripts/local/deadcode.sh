#!/usr/bin/env bash
set -euo pipefail

mode="${1:-}"
[ -z "${mode}" ] && echo "❌ deadcode mode not set" >&2 && exit 1

# One line per mode and component script; a composite mode repeats its name once per component, in run order.
# `strict` puts the two staticcheck components ahead of the unchanged deadcode strict sequence and its lax feed.
plan="$(
  awk -v mode="${mode}" '$1 == mode { print $2 }' <<'PLAN'
staticcheck-whole scripts/local/staticcheck-whole.sh
deadcode-whole scripts/local/deadcode-whole.sh
staticcheck-production scripts/local/staticcheck-production.sh
deadcode-production scripts/local/deadcode-production.sh
lax scripts/local/deadcode-lax.sh
strict scripts/local/staticcheck-whole.sh
strict scripts/local/staticcheck-production.sh
strict scripts/local/deadcode-strict.sh
PLAN
)"
[ -z "${plan}" ] && echo "❌ unknown deadcode mode '${mode}'" >&2 && exit 1

# A composite mode resolves to several components, so the plan is run one line at a time.
while IFS= read -r runner; do
  [ ! -x "./${runner}" ] && echo "❌ deadcode component './${runner}' is not executable" >&2 && exit 1
  "./${runner}"
done <<<"${plan}"

echo "✅ Go deadcode ${mode} plan complete"
