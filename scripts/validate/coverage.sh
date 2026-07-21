#!/usr/bin/env bash
set -euo pipefail

mode="${1:-}"
mkdir -p coverage reports

case "$mode" in
unit)
  tests=(test/unit test/conformance)
  include='lib/(src/|diene_config[.]dart)'
  minimum=90
  ;;
meta)
  tests=(test/meta)
  include='lib/test_helper[.]dart'
  minimum=95
  ;;
*)
  echo "usage: $0 unit|meta" >&2
  exit 2
  ;;
esac

report="coverage/${mode}.lcov"
dart test "${tests[@]}" --coverage-path "$report"

awk -v path_pattern="$include" -v minimum="$minimum" -v mode="$mode" '
  /^SF:/ { active = substr($0, 4) ~ path_pattern }
  active && /^LF:/ { total += substr($0, 4) }
  active && /^LH:/ { hit += substr($0, 4) }
  END {
    if (total == 0) {
      print "❌ " mode " coverage selected no lines" > "/dev/stderr"
      exit 1
    }
    percent = (100 * hit) / total
    printf "%s coverage: %.2f%% (%d/%d), minimum %d%%\n", mode, percent, hit, total, minimum
    if (percent + 0.0001 < minimum) exit 1
  }
' "$report" | tee "reports/coverage-${mode}.txt"
