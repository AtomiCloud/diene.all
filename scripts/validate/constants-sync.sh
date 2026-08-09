#!/usr/bin/env bash
set -euo pipefail

root_dir="$(git rev-parse --show-toplevel)"
cd "${root_dir}"
settings="config/settings.yaml"
constants="src/config/constants.ts"

echo "🔑 Checking keyed adapter constants..."
for pair in 'postgres:Postgres' 'cache:Cache' 'kv:Kv' 'storage:Storage'; do
  block="${pair%%:*}"
  symbol="${pair##*:}"
  yaml_keys="$(yq -r ".${block} | keys | .[]" "${settings}" | sort)"
  ts_keys="$(rg "^export const ${symbol} =" "${constants}" | rg -o "'[A-Z][A-Z0-9_]*'" | tr -d "'" | sort)"
  [[ ${yaml_keys} != "${ts_keys}" ]] && echo "❌ ${block} keys differ between ${settings} and ${constants}" >&2 && exit 1
done
echo "✅ Keyed adapter constants match configuration"
