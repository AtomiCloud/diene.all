#!/usr/bin/env bash
set -euo pipefail

tag="${1:-${GITHUB_REF_NAME:-}}"
module="$(yq -r '.module' .config/go-lib.yaml)"
proxy="${GOPROXY_URL:-$(yq -r '.proxy' .config/go-lib.yaml)}"
consumer_source="$(pwd)/scripts/validate/proxy-consumer.go.txt"
tmp="$(mktemp -d)"
trap 'chmod -R u+w "${tmp}" 2>/dev/null || true; rm -rf "${tmp}"' EXIT

./scripts/validate/go-publish-guard.sh "${tag}"

# Isolate every Go cache and clear the private/direct routing variables so the
# resolution is proven against the public proxy and checksum database, never a
# warm cache or a private route (isolated public caches).
export GOMODCACHE="${tmp}/modcache"
export GOCACHE="${tmp}/gocache"
export GOPATH="${tmp}/gopath"
export GOFLAGS=-mod=mod
export GOPROXY="${proxy}"
export GOSUMDB=sum.golang.org
export GOPRIVATE=""
export GONOPROXY=""
export GONOSUMDB=""
export GONOSUMCHECK=""

cd "${tmp}"
go mod init example.invalid/go-lib-consumer >/dev/null
go get "${module}@${tag}"

# Copy the single tracked consumer source and bind it to the published module.
sed "s#__MODULE__#${module}#g" "${consumer_source}" >main.go
go mod tidy
go build -o consumer .
[ "$(./consumer)" != "config overlay 9.9.9" ] && echo "❌ proxy consumer returned an unexpected result" >&2 && exit 1

# Record durable version/checksum evidence facts for R-E22/R-E25 closure.
echo "proxy roundtrip evidence:"
echo "  module: ${module}@${tag}"
go list -m -f '  resolved: {{.Path}}@{{.Version}}' "${module}"
grep "^${module} " go.sum || true

echo "✅ Go proxy resolved ${module}@${tag} into a clean three-layer consumer"
