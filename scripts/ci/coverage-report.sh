#!/usr/bin/env bash
set -euo pipefail

# Reports line coverage from an lcov file and enforces a single high threshold
# per ledger. The unit ledger (product code) and the meta ledger (TestHelper
# code) each call this with their own lcov file so the two ledgers stay
# separate, as the family testing rules require.
#
# Usage: coverage-report.sh <lcov-file> <ledger-name>
# Threshold override: COVERAGE_THRESHOLD (default 90).

lcov="${1:-}"
ledger="${2:-coverage}"
threshold="${COVERAGE_THRESHOLD:-90}"

[ -z "${lcov}" ] && echo "❌ lcov file argument not set" >&2 && exit 1
[ ! -f "${lcov}" ] && echo "❌ lcov file '${lcov}' not found" >&2 && exit 1

found=0
hit=0
while IFS= read -r line; do
  case "${line}" in
  LF:*) found=$((found + ${line#LF:})) ;;
  LH:*) hit=$((hit + ${line#LH:})) ;;
  esac
done <"${lcov}"

if [ "${found}" -eq 0 ]; then
  echo "❌ ${ledger} ledger: no lines instrumented in ${lcov}" >&2
  exit 1
fi

pct=$(((hit * 100) / found))
echo "ℹ️  ${ledger} ledger: ${hit}/${found} lines (${pct}%), threshold ${threshold}%"

if [ "${pct}" -lt "${threshold}" ]; then
  echo "❌ ${ledger} ledger below threshold (${pct}% < ${threshold}%)" >&2
  exit 1
fi
echo "✅ ${ledger} ledger meets threshold"
