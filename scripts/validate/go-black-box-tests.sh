#!/usr/bin/env bash
set -euo pipefail

export_test="$(find . -path ./.git -prune -o -name export_test.go -print -quit)"
[ -n "${export_test}" ] && echo "❌ export_test.go is forbidden: ${export_test}" >&2 && exit 1

subject="$(find . -path ./.git -prune -o -name '*_test.go' -print -quit)"
[ -z "${subject}" ] && echo "❌ no Go test files to inspect: black-box enforcement has no subjects" >&2 && exit 1

violation="$(find . -path ./.git -prune -o -name '*_test.go' -print0 | sort -z | xargs -0 -r gawk -f scripts/validate/go-black-box-tests.awk)"
kind="$(cut -f 1 <<<"${violation}")"
test_file="$(cut -f 2 <<<"${violation}")"
package="$(cut -f 3 <<<"${violation}")"
[ "${kind}" = "MISSING" ] && echo "❌ test package not found: ${test_file}" >&2 && exit 1
[ "${kind}" = "WHITE" ] && echo "❌ white-box test package '${package}' is forbidden: ${test_file}" >&2 && exit 1

echo "✅ Go tests are strict black-box tests"
