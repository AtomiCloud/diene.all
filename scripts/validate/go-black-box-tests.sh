#!/usr/bin/env bash
set -euo pipefail

export_test="$(find . -path ./.git -prune -o -name export_test.go -print -quit)"
[ -n "${export_test}" ] && echo "❌ export_test.go is forbidden: ${export_test}" >&2 && exit 1

while IFS= read -r test_file; do
  package="$(sed -n 's/^package[[:space:]]\+\([[:alnum:]_]*\).*/\1/p' "${test_file}" | head -n 1)"
  [ -z "${package}" ] && echo "❌ test package not found: ${test_file}" >&2 && exit 1
  case "${package}" in
  *_test) ;;
  *) echo "❌ white-box test package '${package}' is forbidden: ${test_file}" >&2 && exit 1 ;;
  esac
done < <(find . -path ./.git -prune -o -name '*_test.go' -print | sort)

echo "✅ Go tests are strict black-box tests"
