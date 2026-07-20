#!/usr/bin/env bash
set -euo pipefail

mode="${1:-}"
[ -z "${mode}" ] && echo "❌ deadcode mode not set" >&2 && exit 1

strict_deadcode() {
  local report
  report="$(deadcode -json "$@")"
  jq -e '(. // []) | length == 0' <<<"${report}" >/dev/null || {
    jq . <<<"${report}" >&2
    return 1
  }
}

case "${mode}" in
whole)
  staticcheck -tests=true ./...
  strict_deadcode -test ./...
  ;;
production)
  staticcheck -tests=false ./...
  runner="$(mktemp -d ./deadcode-runner.XXXXXX)"
  trap 'rm -rf "${runner}"' EXIT
  cp tests/fixtures/deadcode-consumer.go.txt "${runner}/main.go"
  strict_deadcode ./...
  rm -rf "${runner}"
  trap - EXIT
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
