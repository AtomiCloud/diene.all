#!/usr/bin/env bash
set -euo pipefail

baseline="$(yq -r '.apiBaseline' .config/go-lib.yaml)"
candidate="$(yq -r '.apiCandidate' .config/go-lib.yaml)"
module="$(yq -r '.module' .config/go-lib.yaml)"
proxy_module="$(yq -r '.proxyModule' .config/go-lib.yaml)"
fixture="tests/fixtures/api-baseline"
tmp="$(mktemp -d)"
trap 'chmod -R u+w "${tmp}" 2>/dev/null || true; rm -rf "${tmp}"' EXIT

proxy="${tmp}/proxy"
source="${tmp}/${module}@${baseline}"
release="${tmp}/release"
version_dir="${proxy}/${proxy_module}/@v"
mkdir -p "${source}" "${version_dir}" "${release}"
cp -R "${fixture}/." "${source}/"
printf 'module %s\n\ngo 1.26.0\n' "${module}" >"${source}/go.mod"
printf '%s\n' "${baseline}" >"${version_dir}/list"
printf '{"Version":"%s","Time":"2026-01-01T00:00:00Z"}\n' "${baseline}" >"${version_dir}/${baseline}.info"
cp "${source}/go.mod" "${version_dir}/${baseline}.mod"
(cd "${tmp}" && zip -q -r "${version_dir}/${baseline}.zip" "${module}@${baseline}")
tar --exclude=.git --exclude=.github --exclude=.direnv --exclude=coverage --exclude=dist --exclude=reports --exclude=tests -cf - . | tar -C "${release}" -xf -

(cd "${release}" && GOPATH="${tmp}/gopath" GOMODCACHE="${tmp}/modcache" GOCACHE="${tmp}/gocache" GOPROXY="file://${proxy},https://proxy.golang.org" GOSUMDB=off GONOPROXY='' GONOSUMDB='' gorelease -base="${baseline}" -version="${candidate}")

echo "✅ Go public API is compatible with ${baseline}"
