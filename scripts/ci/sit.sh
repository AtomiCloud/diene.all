#!/usr/bin/env bash
set -euo pipefail

# System integration tests. The collection runs headless against the Garden-managed
# `castform` preview supplied by the environments segment — no Testcontainers, no fakes at
# this tier (R8/G1). `--bail` stops at the first failing request so a broken contract is
# reported as itself rather than as a cascade.

collection="${SIT_COLLECTION:-tests/sit/bruno}"
environment="${SIT_ENVIRONMENT:-sit}"
results="${SIT_RESULTS:-TestResults/sit}"

[ ! -d "${collection}" ] && echo "❌ Bruno collection '${collection}' does not exist" >&2 && exit 1
[ ! -f "${collection}/bruno.json" ] && echo "❌ '${collection}' has no bruno.json" >&2 && exit 1
[ ! -f "${collection}/environments/${environment}.bru" ] && echo "❌ '${collection}' has no '${environment}' environment" >&2 && exit 1

# An empty collection would let `bru run` exit 0 and report a green SIT tier that asserted
# nothing at all, so the request count is a precondition rather than a statistic.
requests="$(find "${collection}" -type f -name '*.bru' -not -path "${collection}/environments/*" | wc -l | tr -d ' ')"
[ "${requests}" -eq 0 ] && echo "❌ '${collection}' contains no requests" >&2 && exit 1
echo "📝 ${requests} request file(s) in ${collection}, environment '${environment}'"

./scripts/ci/setup.sh

report="$(pwd)/${results}/sit.junit.xml"
mkdir -p "$(dirname "${report}")"

echo "🔨 running Bruno SIT"
cd "${collection}"
bru run --recursive --env "${environment}" --reporter-junit "${report}" --bail

echo "📝 report written to ${report}"
echo "✅ SIT suite complete"
