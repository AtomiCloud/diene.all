#!/usr/bin/env bash
set -euo pipefail

[ "$#" -gt 0 ] || {
  echo "❌ pass at least one authored-manifest path" >&2
  exit 2
}

if rg -n \
  --glob '*.yaml' \
  --glob '*.yml' \
  --glob '*.tpl' \
  'external-secrets\.io/v1beta1' "$@"; then
  echo "❌ cobalt-authored manifests must use external-secrets.io/v1" >&2
  exit 1
fi

echo "✅ cobalt-authored manifests use external-secrets.io/v1"
