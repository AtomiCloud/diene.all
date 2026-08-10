#!/usr/bin/env bash
set -euo pipefail

echo "🔍 Running production deadcode without test reachability"
# ### go-consumer-deadcode-production-consumer
# #### source: go-consumer
# Materialise the synthetic consumer as a real main package inside the module,
# exactly as every diene Go library does (source: diene.go-otel). It gives the
# goal-mandated SIT and integration SEAMS a real caller WITHOUT excluding,
# filtering or nolint-ing anything: the pass still analyses every production
# package and still reddens on a genuine test-only export. See the header of
# tests/fixtures/deadcode-consumer.go.txt for why that is a classification
# rather than a suppression, and for the rule on adding entries.
runner="$(mktemp -d ./deadcode-runner.XXXXXX)"
trap 'rm -rf "${runner}"' EXIT
cp tests/fixtures/deadcode-consumer.go.txt "${runner}/main.go"
report="$(deadcode -json ./...)"
rm -rf "${runner}"
trap - EXIT
# deadcode prints `null` when it finds nothing, so an empty report means it never looked.
[ -z "${report}" ] && echo "❌ production deadcode produced no report" >&2 && exit 1
count="$(jq '(. // []) | length' <<<"${report}")"
[ "${count}" -ne 0 ] && jq . <<<"${report}" >&2 && exit 1

echo "✅ Go deadcode production pass complete"
