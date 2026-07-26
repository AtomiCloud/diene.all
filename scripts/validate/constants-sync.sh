#!/usr/bin/env bash
set -euo pipefail

root_dir="$(git rev-parse --show-toplevel)"
cd "${root_dir}"
settings="config/settings.yaml"
constants="lib/appconfig/constants.go"
config_rows="$(mktemp)"
constant_rows="$(mktemp)"
unmatched_rows="$(mktemp)"
trap 'rm -f "${config_rows}" "${constant_rows}" "${unmatched_rows}"' EXIT

echo "🔑 Checking keyed adapter constants..."
# shellcheck disable=SC2016  # $block is a yq variable, not a shell variable.
yq -r '
  to_entries
  | map(select(.key == "postgres" or .key == "cache" or .key == "kv" or .key == "storage"))
  | .[] as $block
  | $block.value
  | keys[]
  | ($block.key + ":" + .)
' "${settings}" | sort -u >"${config_rows}"
awk '
  match($0, /^[[:space:]]*(Postgres|Cache|Kv|Storage)([A-Za-z0-9]+)[[:space:]]*=[[:space:]]*"([A-Z][A-Z0-9_]*)"/, fields) {
    block = tolower(fields[1]); print block ":" fields[3]
  }
' "${constants}" | sort -u >"${constant_rows}"
config_count="$(wc -l <"${config_rows}" | tr -d ' ')"
constant_count="$(wc -l <"${constant_rows}" | tr -d ' ')"
[ "${config_count}" -ne 0 ] || {
  echo "❌ no keyed adapter blocks found in ${settings} — refusing an empty match" >&2
  exit 1
}
[ "${constant_count}" -ne 0 ] || {
  echo "❌ no typed keyed-adapter constants found in ${constants} — refusing an empty match" >&2
  exit 1
}
comm -3 "${config_rows}" "${constant_rows}" >"${unmatched_rows}"
unmatched_count="$(wc -l <"${unmatched_rows}" | tr -d ' ')"
echo "${config_count} config keys, ${constant_count} constants, ${unmatched_count} unmatched"
[ "${unmatched_count}" -ne 0 ] && sed 's/^/❌ /' "${unmatched_rows}" >&2 && exit 1
echo "✅ Keyed adapter constants match configuration"
