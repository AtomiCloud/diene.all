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

# Assert durable version/checksum evidence facts for R-E22/R-E25 closure: the
# module must resolve to exactly module@tag and its checksum line must be
# present. These fail the evidence path rather than silently continuing.
resolved="$(go list -m -f '{{.Path}}@{{.Version}}' "${module}")"
[ "${resolved}" != "${module}@${tag}" ] && echo "❌ resolved ${resolved}, expected ${module}@${tag}" >&2 && exit 1
# Fixed-string (-F) matching treats the module path's dots literally and fails
# closed: a missing checksum line makes grep exit non-zero, which the explicit
# guard turns into an evidence-path failure rather than an empty capture.
if ! module_sum="$(grep -F "${module} ${tag} h1:" go.sum)"; then
  echo "❌ module checksum line absent from go.sum for ${module}@${tag}" >&2
  exit 1
fi
if ! gomod_sum="$(grep -F "${module} ${tag}/go.mod h1:" go.sum)"; then
  echo "❌ go.mod checksum line absent from go.sum for ${module}@${tag}" >&2
  exit 1
fi
echo "proxy roundtrip evidence:"
echo "  module:   ${module}@${tag}"
echo "  resolved: ${resolved}"
echo "  ${module_sum}"
echo "  ${gomod_sum}"

echo "✅ Go proxy resolved ${module}@${tag} into a clean three-layer consumer"
