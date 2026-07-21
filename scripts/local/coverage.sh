#!/usr/bin/env bash
set -euo pipefail

mode="${1:-}"
[ -z "${mode}" ] && echo "❌ coverage mode not set" >&2 && exit 1

output="coverage/${mode}"
rm -rf "${output}"
mkdir -p "${output}"

case "${mode}" in
unit)
  dart test --coverage="${output}/raw" test/unit test/conformance
  scope='/lib/(diene_interfaces[.]dart|src/)'
  ;;
meta)
  dart test --coverage="${output}/raw" test/meta
  scope='/lib/test_helper[.]dart'
  ;;
*)
  echo "❌ unknown coverage mode '${mode}'" >&2
  exit 1
  ;;
esac

dart run coverage:format_coverage \
  --lcov \
  --in="${output}/raw" \
  --out="${output}/all.lcov.info" \
  --package=. \
  --report-on=lib

awk -v scope="${scope}" '
  BEGIN { RS = "end_of_record\n"; ORS = "" }
  $0 ~ scope { print $0 "end_of_record\n" }
' "${output}/all.lcov.info" >"${output}/lcov.info"

./scripts/validate/coverage.sh "${mode}" "${output}/lcov.info" 90
echo "✅ Dart ${mode} coverage passed"
