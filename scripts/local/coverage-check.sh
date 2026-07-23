#!/usr/bin/env bash
set -euo pipefail

mode="${1:-}"
[[ ${mode} != "unit" && ${mode} != "int" && ${mode} != "meta" ]] && echo "❌ usage: $0 <unit|int|meta>" >&2 && exit 2

root_dir="$(git rev-parse --show-toplevel)"
cd "${root_dir}"

scope="src/lib/"
[[ ${mode} == "int" ]] && scope="src/adapters/"
[[ ${mode} == "meta" ]] && scope="src/test-helper/"
coverage_file="coverage/${mode}/lcov.info"
source_list="$(mktemp)"
coverage_list="$(mktemp)"
trap 'rm -f "${source_list}" "${coverage_list}"' EXIT

[[ ! -f ${coverage_file} ]] && echo "❌ No coverage artifact found at ${coverage_file}" >&2 && exit 1

awk -v scope="${scope}" '
  BEGIN { files = 0; lines_found = 0; lines_hit = 0; bad = 0 }
  /^SF:/ {
    path = substr($0, 4)
    gsub(/\\\\/, "/", path)
    files++
    if (path !~ "(^|/)" scope) {
      printf "❌ coverage path outside %s: %s\n", scope, path > "/dev/stderr"
      bad = 1
    }
  }
  /^LF:/ { lines_found += substr($0, 4) + 0 }
  /^LH:/ { lines_hit += substr($0, 4) + 0 }
  END {
    if (files == 0) {
      print "❌ coverage ledger contains no source files" > "/dev/stderr"
      exit 1
    }
    if (lines_found == 0) {
      print "❌ coverage ledger contains no executable lines" > "/dev/stderr"
      exit 1
    }
    if (lines_hit != lines_found) {
      printf "❌ coverage is not 100%%: %d/%d lines hit\n", lines_hit, lines_found > "/dev/stderr"
      exit 1
    }
    if (bad != 0) exit 1
  }
' "${coverage_file}"

rg -l --glob '*.ts' '^(export )?(async )?(function|class|const|let|var|enum)\b|^[[:space:]]*(const|let|var)\b' "${scope%/}" | sort -u >"${source_list}"
awk '
  /^SF:/ {
    path = substr($0, 4)
    gsub(/\\\\/, "/", path)
    sub(/^.*\/src\//, "src/", path)
    print path
  }
' "${coverage_file}" | sort -u >"${coverage_list}"
missing="$(comm -23 "${source_list}" "${coverage_list}" | head -n 1)"
[[ -n ${missing} ]] && echo "❌ source file missing from coverage ledger: ${missing}" >&2 && exit 1

echo "✅ Coverage artifact is scoped to ${scope}: ${coverage_file}"
