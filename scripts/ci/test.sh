#!/usr/bin/env bash
set -euo pipefail

mode="${1:-}"
[[ ${mode} != "unit" && ${mode} != "int" ]] && echo "❌ usage: $0 <unit|int>" >&2 && exit 2

root_dir="$(git rev-parse --show-toplevel)"
cd "${root_dir}"

./scripts/ci/setup.sh

config="bunfig.${mode}.toml"
coverage_file="coverage/${mode}/lcov.info"
scope="src/lib/"
[[ ${mode} == "int" ]] && scope="src/adapters/"

echo "🧪 Running ${mode} tests with coverage..."
rm -rf "coverage/${mode}"

# The test tool owns the verdict. bunfig.${mode}.toml carries `coverageThreshold = 1.0`,
# so a shortfall is bun's own non-zero exit, and its `preload` ledger imports every
# module in the tier so an untested file is measured at 0% instead of vanishing from the
# report. Neither property needs a script wrapped around bun to hold.
bun test --config="${config}" --coverage

# What bun does NOT decide is which tier a source belongs to, so that — and only that —
# is lint-checked here, on the machine-readable artifact rather than on bun's human
# output. Absence is its own refusal: rg exits 2 on a missing file, so a deleted artifact
# would otherwise turn this into a silent pass.
[[ -f ${coverage_file} ]] || { echo "❌ no coverage artifact at ${coverage_file}" >&2; exit 1; }
sources="$(rg -N --replace '' '^SF:' "${coverage_file}" || true)"
[[ -z ${sources} ]] && echo "❌ coverage ledger at ${coverage_file} names no source file" >&2 && exit 1
outside="$(printf '%s\n' "${sources}" | rg -v "(^|/)${scope}" || true)"
[[ -n ${outside} ]] && echo "❌ coverage path outside ${scope}: ${outside}" >&2 && exit 1

echo "✅ ${mode} tests passed; coverage is complete and scoped to ${scope}: ${coverage_file}"
