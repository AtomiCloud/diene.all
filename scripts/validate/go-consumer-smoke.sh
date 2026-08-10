#!/usr/bin/env bash
set -euo pipefail

# Branch-safe companion to go-proxy-roundtrip.sh: it compiles and runs the EXACT
# same tracked consumer source (scripts/validate/proxy-consumer.go.txt) against
# the CURRENT local module via a replace directive, so the tag-only scratch
# consumer's compile and three-layer behavior are proven on every branch before
# a public tag exists. The proxy round trip then re-proves it against the
# published module at publish time.
module="$(yq -r '.module' .config/go-lib.yaml)"
worktree="$(pwd)"
consumer_source="${worktree}/scripts/validate/proxy-consumer.go.txt"
[ -f "${consumer_source}" ] || {
  echo "❌ consumer source missing: ${consumer_source}" >&2
  exit 1
}
tmp="$(mktemp -d)"
trap 'chmod -R u+w "${tmp}" 2>/dev/null || true; rm -rf "${tmp}"' EXIT

cd "${tmp}"
go mod init example.invalid/go-consumer-smoke >/dev/null
sed "s#__MODULE__#${module}#g" "${consumer_source}" >main.go
go mod edit -require="${module}@v0.0.0"
go mod edit -replace="${module}=${worktree}"
go mod tidy
go build -o consumer .
[ "$(./consumer)" != "config overlay 9.9.9" ] && echo "❌ branch-safe consumer returned an unexpected result" >&2 && exit 1

echo "✅ Branch-safe consumer compiled and ran the tag-only source against the local module"
