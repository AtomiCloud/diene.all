#!/usr/bin/env bash
set -euo pipefail

config="${1:-}"
coverage_mode="${2:-}"
[ -z "${config}" ] && echo "❌ usage: $0 <bunfig-meta-config> [coverage]" >&2 && exit 2
[[ -n ${coverage_mode} && ${coverage_mode} != "coverage" ]] && echo "❌ optional mode must be 'coverage'" >&2 && exit 2

root_dir="$(git rev-parse --show-toplevel)"
cd "${root_dir}"

[[ ${coverage_mode} == "coverage" ]] && rm -rf coverage/meta

helper_source="$(find src/test-helper -type f -name '*.ts' -print -quit 2>/dev/null || true)"
meta_test="$(find tests/meta -type f -name '*.test.ts' -print -quit 2>/dev/null || true)"
[[ -z ${helper_source} && -z ${meta_test} ]] && echo "⏭️ No TestHelper or meta tests exist; meta tier is a successful no-op" && exit 0
[[ -z ${helper_source} || -z ${meta_test} ]] && echo "❌ TestHelper source and meta tests must be added together" >&2 && exit 1

[[ ${coverage_mode} == "coverage" ]] && bun test --config="${config}" --coverage
[[ -z ${coverage_mode} ]] && bun test --config="${config}"

echo "✅ Meta tests passed"
