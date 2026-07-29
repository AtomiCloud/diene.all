#!/usr/bin/env bash
set -euo pipefail

# System integration tests. The collection runs headless against the Garden-managed
# `castform` preview supplied by the environments segment — no Testcontainers, no fakes at
# this tier (R8/G1). `--bail` stops at the first failing request so a broken contract is
# reported as itself rather than as a cascade.

collection="${SIT_COLLECTION:-tests/sit/bruno}"
environment="${SIT_ENVIRONMENT:-sit}"
results="${SIT_RESULTS:-TestResults/sit}"
root="$(pwd)"

[ ! -d "${collection}" ] && echo "❌ Bruno collection '${collection}' does not exist" >&2 && exit 1
[ ! -f "${collection}/bruno.json" ] && echo "❌ '${collection}' has no bruno.json" >&2 && exit 1
[ ! -f "${collection}/environments/${environment}.bru" ] && echo "❌ '${collection}' has no '${environment}' environment" >&2 && exit 1

# An empty collection would let `bru run` exit 0 and report a green SIT tier that asserted
# nothing at all, so the request count is a precondition rather than a statistic.
requests="$(find "${collection}" -type f -name '*.bru' -not -path "${collection}/environments/*" | wc -l | tr -d ' ')"
[ "${requests}" -eq 0 ] && echo "❌ '${collection}' contains no requests" >&2 && exit 1
echo "📝 ${requests} request file(s) in ${collection}, environment '${environment}'"

./scripts/ci/setup.sh

report="${root}/${results}/sit.junit.xml"
mkdir -p "$(dirname "${report}")"
rm -f "${report}"

# `-r` is the recursion flag. The long form `--recursive` is REJECTED by bru, and without
# recursion bru runs only root-level requests — every journey here lives in a numbered
# folder, so a non-recursive run reports success having executed nothing.
echo "🔨 running Bruno SIT"
cd "${collection}"
set +e
bru run -r --env "${environment}" --reporter-junit "${report}" --bail
bru_rc=$?
set -e
cd "${root}"

# bru's exit code alone is not the whole signal: a run that matched no requests can exit 0.
# The junit report is the artifact CI keeps, so the counts are read back out of it with a
# structured query rather than a grep, and the tier fails if it asserted nothing.
[ ! -f "${report}" ] && echo "❌ bru produced no junit report at ${report} (rc=${bru_rc})" >&2 && exit 1
total="$(xmlstarlet sel -t -v 'sum(//testsuite/@tests)' -n "${report}")"
failures="$(xmlstarlet sel -t -v 'sum(//testsuite/@failures)' -n "${report}")"
errors="$(xmlstarlet sel -t -v 'sum(//testsuite/@errors)' -n "${report}")"

# XPath sum() yields NaN rather than an error on a malformed report, and NaN would sail
# straight through the arithmetic below as a silent zero.
case "${total}|${failures}|${errors}" in
*[!0-9\|]*)
  echo "❌ junit counters are not numeric (tests=${total} failures=${failures} errors=${errors})" >&2
  exit 1
  ;;
esac
passed=$((total - failures - errors))

echo "📝 SIT results: ${passed} passed / ${total} total (${failures} failure(s), ${errors} error(s))"
echo "📝 report written to ${report}"

[ "${total}" -eq 0 ] && echo "❌ SIT executed 0 assertions; a green run that asserted nothing is not a pass" >&2 && exit 1
[ "${bru_rc}" -ne 0 ] && echo "❌ bru exited ${bru_rc}" >&2 && exit "${bru_rc}"
[ $((failures + errors)) -ne 0 ] && echo "❌ ${failures} failure(s) and ${errors} error(s) in the SIT tier" >&2 && exit 1

echo "✅ SIT suite complete: ${passed}/${total} passed"
