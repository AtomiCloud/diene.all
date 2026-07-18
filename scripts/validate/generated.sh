#!/usr/bin/env bash
set -euo pipefail

mode="${1:-}"
[ "${mode}" != "sdk" ] && [ "${mode}" != "translations" ] && [ "${mode}" != "config" ] && echo "❌ mode must be sdk, translations, or config" >&2 && exit 1

if [ "${mode}" = "sdk" ]; then
  ./scripts/local/generate-sdk.sh
  git diff --exit-code -- lib/generated/service || {
    echo "❌ generated OA3 client is stale" >&2
    exit 1
  }
elif [ "${mode}" = "translations" ]; then
  ./scripts/local/generate-translations.sh
  git diff --exit-code -- lib/i18n/translations.g.dart lib/i18n/translations_en.g.dart lib/i18n/translations_es.g.dart || {
    echo "❌ generated Slang translations are stale" >&2
    exit 1
  }
else
  tmp="$(mktemp)"
  expected="$(mktemp)"
  actual="$(mktemp)"
  trap 'rm -f "${tmp}" "${expected}" "${actual}"' EXIT
  bun tool/generate-config-schema.ts >"${tmp}"
  jq -S . "${tmp}" >"${expected}"
  jq -S . config/schema.json >"${actual}"
  cmp -s "${expected}" "${actual}" || {
    echo "❌ config/schema.json is stale" >&2
    exit 1
  }
fi

echo "✅ ${mode} generated output is fresh"
