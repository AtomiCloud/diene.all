#!/usr/bin/env bash
set -euo pipefail

mode="${1:-}"
[ -z "${mode}" ] && echo "❌ deadcode mode not set" >&2 && exit 1

case "${mode}" in
whole)
  staticcheck -tests=true ./...
  report="$(deadcode -json -test ./...)"
  jq -e '(. // []) | length == 0' <<<"${report}" >/dev/null || {
    jq . <<<"${report}" >&2
    exit 1
  }
  ;;
production)
  staticcheck -tests=false ./...
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
  jq -e '(. // []) | length == 0' <<<"${report}" >/dev/null || {
    jq . <<<"${report}" >&2
    exit 1
  }
  ;;
lax)
  mkdir -p reports
  {
    echo "# Whole repository candidates"
    staticcheck -tests=true ./... || true
    deadcode -test ./... || true
    echo "# Production candidates"
    staticcheck -tests=false ./... || true
    deadcode ./... || true
  } >reports/deadcode-llm.txt 2>&1
  ;;
strict)
  ./scripts/local/deadcode.sh whole
  ./scripts/local/deadcode.sh production
  ./scripts/local/deadcode.sh lax
  ;;
*)
  echo "❌ unknown deadcode mode '${mode}'" >&2
  exit 1
  ;;
esac

echo "✅ Go deadcode ${mode} pass complete"
