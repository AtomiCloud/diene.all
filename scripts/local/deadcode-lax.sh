#!/usr/bin/env bash
set -euo pipefail

# Candidates stay nonblocking; a scanner that could not run or load is fatal (staticcheck marks those `compile`), and every pass records completion.
report="reports/deadcode-llm.txt"
scan="$(mktemp)"
trap 'rm -f "${scan}"' EXIT

mkdir -p reports

echo "📝 Collecting whole-repository candidates"
echo "# Whole repository candidates" >"${report}"

whole_staticcheck=0
staticcheck -tests=true ./... >"${scan}" 2>&1 || whole_staticcheck=$?
cat "${scan}" >>"${report}"
[ "${whole_staticcheck}" -gt 1 ] && echo "❌ whole-repository staticcheck could not run (exit ${whole_staticcheck})" >&2 && exit 1
grep -q ' (compile)$' "${scan}" && echo "❌ whole-repository staticcheck could not load the packages" >&2 && exit 1
echo "## pass complete: whole-repository staticcheck (exit ${whole_staticcheck}, lines $(grep -c '^' "${scan}" || true))" >>"${report}"

whole_deadcode=0
deadcode -test ./... >"${scan}" 2>&1 || whole_deadcode=$?
cat "${scan}" >>"${report}"
[ "${whole_deadcode}" -ne 0 ] && echo "❌ whole-repository deadcode could not run (exit ${whole_deadcode})" >&2 && exit 1
echo "## pass complete: whole-repository deadcode (exit ${whole_deadcode}, lines $(grep -c '^' "${scan}" || true))" >>"${report}"

echo "📝 Collecting production candidates"
echo "# Production candidates" >>"${report}"

production_staticcheck=0
staticcheck -tests=false ./... >"${scan}" 2>&1 || production_staticcheck=$?
cat "${scan}" >>"${report}"
[ "${production_staticcheck}" -gt 1 ] && echo "❌ production staticcheck could not run (exit ${production_staticcheck})" >&2 && exit 1
grep -q ' (compile)$' "${scan}" && echo "❌ production staticcheck could not load the packages" >&2 && exit 1
echo "## pass complete: production staticcheck (exit ${production_staticcheck}, lines $(grep -c '^' "${scan}" || true))" >>"${report}"

production_deadcode=0
deadcode ./... >"${scan}" 2>&1 || production_deadcode=$?
cat "${scan}" >>"${report}"
[ "${production_deadcode}" -ne 0 ] && echo "❌ production deadcode could not run (exit ${production_deadcode})" >&2 && exit 1
echo "## pass complete: production deadcode (exit ${production_deadcode}, lines $(grep -c '^' "${scan}" || true))" >>"${report}"

records="$(grep -c '^## pass complete: ' "${report}" || true)"
[ "${records}" -ne 4 ] && echo "❌ lax report holds ${records} of 4 pass completion records" >&2 && exit 1

echo "✅ Go deadcode lax pass complete (4 passes recorded in ${report})"
