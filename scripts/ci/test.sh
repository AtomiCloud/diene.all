#!/usr/bin/env bash
set -euo pipefail

mode="${1:-}"
[[ ${mode} != "unit" && ${mode} != "int" ]] && echo "❌ usage: $0 <unit|int>" >&2 && exit 2

root_dir="$(git rev-parse --show-toplevel)"
cd "${root_dir}"

config="bunfig.${mode}.toml"
coverage_file="coverage/${mode}/lcov.info"
scope="src/lib/"
[[ ${mode} == "int" ]] && scope="src/adapters/"

echo "🧪 Running ${mode} tests with coverage..."
rm -rf "coverage/${mode}"

bun test --config="${config}" --coverage

# rg exits 2 on a missing file, so absence needs its own refusal.
[[ -f ${coverage_file} ]] || {
  echo "❌ no coverage artifact at ${coverage_file}" >&2
  exit 1
}
sources="$(rg -N --replace '' '^SF:' "${coverage_file}" || true)"
[[ -z ${sources} ]] && echo "❌ coverage ledger at ${coverage_file} names no source file" >&2 && exit 1
outside="$(printf '%s\n' "${sources}" | rg -v "(^|/)${scope}" || true)"
[[ -n ${outside} ]] && echo "❌ coverage path outside ${scope}: ${outside}" >&2 && exit 1

echo "✅ ${mode} tests passed; coverage is complete and scoped to ${scope}: ${coverage_file}"
