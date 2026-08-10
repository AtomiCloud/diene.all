#!/usr/bin/env bash
set -euo pipefail

# Filter an lcov ledger to the paths a tier owns, then assert 100% line coverage.
#
# Extracted verbatim from scripts/ci/test.sh. This half carries NO Dart: it is
# awk over lcov records, so it is identical on every descendant that renames its
# package. test.sh is the file the eight dart children rewrite (each substitutes
# its own packages/diene_* member); keeping the generic half out of that file
# means a fix here does not have to be re-applied eight times.
#
# usage: coverage-ledger.sh <all.info> <out.lcov> <sf-pattern> <mode-label>

all_ledger="${1:?usage: coverage-ledger.sh <all.info> <out.lcov> <sf-pattern> <mode-label>}"
ledger="${2:?usage: coverage-ledger.sh <all.info> <out.lcov> <sf-pattern> <mode-label>}"
pattern="${3:?usage: coverage-ledger.sh <all.info> <out.lcov> <sf-pattern> <mode-label>}"
mode="${4:?usage: coverage-ledger.sh <all.info> <out.lcov> <sf-pattern> <mode-label>}"

[[ -f ${all_ledger} ]] || {
  echo "❌ ${mode} coverage: input ledger '${all_ledger}' does not exist" >&2
  exit 1
}

awk -v pattern="${pattern}" '
  /^SF:/ { keep = substr($0, 4) ~ pattern }
  keep { print }
' "${all_ledger}" >"${ledger}"
rm -f "${all_ledger}"

awk -v mode="${mode}" '
  BEGIN { files = 0; lines_found = 0; lines_hit = 0 }
  /^SF:/ { files++ }
  /^LF:/ { lines_found += substr($0, 4) + 0 }
  /^LH:/ { lines_hit += substr($0, 4) + 0 }
  END {
    if (files == 0) {
      printf "❌ %s coverage ledger contains no source files\n", mode > "/dev/stderr"
      exit 1
    }
    if (lines_found == 0) {
      printf "❌ %s coverage ledger contains no executable lines\n", mode > "/dev/stderr"
      exit 1
    }
    if (lines_hit != lines_found) {
      printf "❌ %s coverage is not 100%%: %d/%d lines hit\n", mode, lines_hit, lines_found > "/dev/stderr"
      exit 1
    }
    printf "✅ %s coverage is 100%%: %d/%d lines hit\n", mode, lines_hit, lines_found
  }
' "${ledger}"
