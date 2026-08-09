#!/usr/bin/env bash
set -euo pipefail

en_keys="$(jq -S 'keys' lib/i18n/en.i18n.json)"
es_keys="$(jq -S 'keys' lib/i18n/es.i18n.json)"
[ "${en_keys}" != "${es_keys}" ] && echo "❌ shipped locales do not expose the same typed keys" >&2 && exit 1
flutter test test/generated_contract_test.dart

echo "✅ all shipped translation keys compile"
