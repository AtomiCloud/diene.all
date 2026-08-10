#!/usr/bin/env bash
set -euo pipefail

mode="${1:-}"
[[ ${mode} != "unit" && ${mode} != "int" && ${mode} != "meta" && ${mode} != "sit" ]] && echo "❌ usage: $0 <unit|int|meta|sit>" >&2 && exit 2

root_dir="$(git rev-parse --show-toplevel)"
cd "${root_dir}"

./scripts/ci/setup.sh

if [[ ${mode} == "int" ]]; then
  adapter_source="$(find src/adapters -type f -name '*.ts' -print -quit 2>/dev/null || true)"
  integration_test="$(find tests/integration -type f -name '*.test.ts' -print -quit 2>/dev/null || true)"
  [[ -z ${adapter_source} && -z ${integration_test} ]] && echo "⏭️ No integration tier (this package has no adapters)" && exit 0
  [[ -z ${adapter_source} || -z ${integration_test} ]] && echo "❌ Adapter source and integration tests must be added together" >&2 && exit 1
fi

if [[ ${mode} == "sit" ]]; then
  [[ -d dist/bin ]] && chmod -R +x dist/bin
  [[ -n ${CLI_BIN:-} ]] && chmod +x "${CLI_BIN}"
  echo "🧪 Running sit tests..."
  bun test --config=bunfig.sit.toml
  echo "✅ sit tests passed"
  exit 0
fi

config="bunfig.${mode}.toml"
coverage_dir="coverage/${mode}"
coverage_file="${coverage_dir}/lcov.info"
scope="src/lib/"
[[ ${mode} == "int" ]] && scope="src/adapters/"
[[ ${mode} == "meta" ]] && scope="src/test-helper/"
source_list="$(mktemp)"
coverage_list="$(mktemp)"
trap 'rm -f "${source_list}" "${coverage_list}"' EXIT

rm -rf "${coverage_dir}"

if [[ ${mode} == "meta" ]]; then
  helper_source="$(find src/test-helper -type f -name '*.ts' -print -quit 2>/dev/null || true)"
  meta_test="$(find tests/meta -type f -name '*.test.ts' -print -quit 2>/dev/null || true)"
  [[ -z ${helper_source} && -z ${meta_test} ]] && echo "⏭️ No TestHelper or meta tests exist; meta tier is a successful no-op" && exit 0
  [[ -z ${helper_source} || -z ${meta_test} ]] && echo "❌ TestHelper source and meta tests must be added together" >&2 && exit 1
fi

echo "🧪 Running ${mode} tests with coverage..."

set +e
if [[ ${mode} == "meta" ]]; then
  ./scripts/local/test-meta.sh "${config}" coverage
else
  bun test --config="${config}" --coverage
fi
test_status=$?
set -e

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
[[ ${test_status} -ne 0 ]] && echo "❌ ${mode} tests failed (exit ${test_status})" >&2 && exit "${test_status}"
echo "✅ ${mode} tests passed"
