#!/usr/bin/env bash
set -euo pipefail

baseline="$(yq -r '.apiBaseline' .config/go-lib.yaml)"
candidate="$(yq -r '.apiCandidate' .config/go-lib.yaml)"
module="$(yq -r '.module' .config/go-lib.yaml)"
proxy_module="$(yq -r '.proxyModule' .config/go-lib.yaml)"
fixture="tests/fixtures/api-baseline"
tmp="$(mktemp -d)"
trap 'rm -rf "${tmp}"' EXIT

proxy="${tmp}/proxy"
source="${tmp}/${module}@${baseline}"
release="${tmp}/release"
problem_module="github.com/AtomiCloud/diene.go-errors-problems"
problem_proxy_module="github.com/!atomi!cloud/diene.go-errors-problems"
problem_version="v1.0.0"
problem_source="${tmp}/${problem_module}@${problem_version}"
problem_version_dir="${proxy}/${problem_proxy_module}/@v"
version_dir="${proxy}/${proxy_module}/@v"
mkdir -p "${source}" "${version_dir}" "${release}" "${problem_source}" "${problem_version_dir}"
cp -R "${fixture}/." "${source}/"
printf 'module %s\n\ngo 1.26.0\n' "${module}" >"${source}/go.mod"
printf '%s\n' "${baseline}" >"${version_dir}/list"
printf '{"Version":"%s","Time":"2026-01-01T00:00:00Z"}\n' "${baseline}" >"${version_dir}/${baseline}.info"
cp "${source}/go.mod" "${version_dir}/${baseline}.mod"
(cd "${tmp}" && zip -q -r "${version_dir}/${baseline}.zip" "${module}@${baseline}")
tar --exclude=.git --exclude=.direnv --exclude=coverage --exclude=dist --exclude=reports -cf - . | tar -C "${release}" -xf -
tar --exclude=.git --exclude=.direnv --exclude=coverage --exclude=dist --exclude=reports -C ../go-errors-problems-mrvtcqah -cf - . | tar -C "${problem_source}" -xf -
printf '%s\n' "${problem_version}" >"${problem_version_dir}/list"
printf '{"Version":"%s","Time":"2026-01-01T00:00:00Z"}\n' "${problem_version}" >"${problem_version_dir}/${problem_version}.info"
cp "${problem_source}/go.mod" "${problem_version_dir}/${problem_version}.mod"
(cd "${tmp}" && zip -q -r "${problem_version_dir}/${problem_version}.zip" "${problem_module}@${problem_version}")

(cd "${release}" && go mod edit -dropreplace="${problem_module}" && GOPROXY="file://${proxy},https://proxy.golang.org" GOSUMDB=off go mod tidy)

(cd "${release}" && GOFLAGS=-mod=mod GOPROXY="file://${proxy},https://proxy.golang.org" GOSUMDB=off gorelease -base="${baseline}" -version="${candidate}")

echo "✅ Go public API is compatible with ${baseline}"
