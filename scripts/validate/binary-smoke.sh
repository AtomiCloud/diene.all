#!/usr/bin/env bash
set -euo pipefail

# ### workspace
# #### source: workspace
root_dir="$(git rev-parse --show-toplevel)"
cd "${root_dir}"

for binary in actionlint bash cyanprint deadcode docker git go gofumpt golangci-lint gomplate gotestsum govulncheck hadolint helm helm-docs infisical jq k3d kubeconform kubectl kyverno mc nix pls pre-commit psql rg sg shellcheck skopeo staticcheck task treefmt yq; do
  command -v "${binary}" >/dev/null || {
    echo "❌ binary '${binary}' is missing" >&2
    exit 1
  }
done

tmp="$(mktemp -d)"
trap 'rm -rf "${tmp}"' EXIT

actionlint -version >/dev/null
printf '%s\n' 'name: Smoke' 'on: push' 'jobs:' '  smoke:' '    runs-on: ubuntu-latest' '    steps:' '      - run: echo smoke' >"${tmp}/workflow.yaml"
actionlint "${tmp}/workflow.yaml"

bash --version >/dev/null
[ "$(bash -c 'printf smoke')" != "smoke" ] && echo "❌ bash failed a real invocation" >&2 && exit 1

mapfile -t cyanprint_versions < <(
  awk -F'"' '/^[[:space:]]*cyanprintVersion = "[^"]+";$/ { print $2 }' nix/packages.nix
)
[ "${#cyanprint_versions[@]}" -ne 1 ] && echo "❌ expected exactly one cyanprintVersion pin in nix/packages.nix" >&2 && exit 1
cyanprint --version | rg -Fxq "cyanprint ${cyanprint_versions[0]}"
mkdir -p "${tmp}/cyanprint-cache"
cyanprint cache inspect --cache-dir "${tmp}/cyanprint-cache" --json | jq -e '.status == "done" and .action == "inspect"' >/dev/null

docker --version >/dev/null
docker info --format '{{.ServerVersion}}' >/dev/null

git --version >/dev/null
git rev-parse --is-inside-work-tree >/dev/null

# ### go-consumer
# #### source: go-consumer
go version >/dev/null
go list ./... >/dev/null

gofumpt -version >/dev/null
printf '%s\n' 'package smoke' 'func Value( )int{return 1}' >"${tmp}/smoke.go"
gofumpt -w "${tmp}/smoke.go"
rg -q 'func Value\(\) int' "${tmp}/smoke.go"

golangci-lint version >/dev/null
golangci-lint run --timeout 5m ./lib/...

gotestsum --version >/dev/null
gotestsum --format pkgname -- --run '^$' ./lib/... >/dev/null

govulncheck -version >/dev/null
GOVULNCHECK_TARGET=./lib/... ./scripts/local/vuln.sh >/dev/null

deadcode -json -test ./... >/dev/null

staticcheck -version >/dev/null
staticcheck -tests=true ./...

gomplate --version >/dev/null
[ "$(gomplate -i '{{ add 1 1 }}')" != "2" ] && echo "❌ gomplate failed a real template" >&2 && exit 1

hadolint --version >/dev/null
hadolint infra/Dockerfile

helm-docs --version >/dev/null
helm-docs --dry-run --chart-search-root infra/root_chart >/dev/null 2>&1

helm version --short >/dev/null
helm template diene-go-consumer infra/root_chart | kubeconform -strict -summary -ignore-missing-schemas >/dev/null

infisical --version >/dev/null
git -C "${tmp}" init -q
git -C "${tmp}" config user.email smoke@example.invalid
git -C "${tmp}" config user.name Smoke
touch "${tmp}/empty"
git -C "${tmp}" add empty
git -C "${tmp}" commit -qm smoke
(cd "${tmp}" && infisical scan . -v >/dev/null 2>&1)

jq --version >/dev/null
jq -en '1 + 1 == 2' >/dev/null

mc --version >/dev/null
mkdir -p "${tmp}/mc-source" "${tmp}/mc-target"
printf '%s\n' 'minio-client-smoke' >"${tmp}/mc-source/object.txt"
MC_CONFIG_DIR="${tmp}/mc-config" mc cp "${tmp}/mc-source/object.txt" "${tmp}/mc-target/object.txt" >/dev/null
cmp "${tmp}/mc-source/object.txt" "${tmp}/mc-target/object.txt"

k3d version >/dev/null
k3d cluster list --no-headers >/dev/null

kubeconform -v >/dev/null

kubectl version --client >/dev/null
kubectl --kubeconfig=/dev/null config view >/dev/null

kyverno version >/dev/null
printf '%s\n' '{"probe":{"ok":true}}' | kyverno jp query 'probe.ok' 2>/dev/null | tail -n 1 | rg -qx true

nix --version >/dev/null
nix flake metadata --no-write-lock-file --json . | jq -e '.url | type == "string"' >/dev/null

pls --help >/dev/null 2>&1
pls --list >/dev/null

pre-commit --version >/dev/null
pre-commit validate-config .pre-commit-config.yaml

psql --version >/dev/null
postgres_host="$(yq -r '.postgres.host // ""' config/dev.yaml 2>/dev/null || true)"
postgres_port="$(yq -r '.postgres.port // ""' config/dev.yaml 2>/dev/null || true)"
postgres_database="$(yq -r '.postgres.database // ""' config/dev.yaml 2>/dev/null || true)"
postgres_username="$(yq -r '.postgres.username // ""' config/dev.yaml 2>/dev/null || true)"
postgres_password="$(yq -r '.postgres.password // ""' config/dev.yaml 2>/dev/null || true)"
if [[ -n ${postgres_host} && -n ${postgres_port} && -n ${postgres_database} && -n ${postgres_username} ]] && psql_result="$(PGPASSWORD="${postgres_password}" PGCONNECT_TIMEOUT=2 PGSSLMODE=disable psql --no-psqlrc --host="${postgres_host}" --port="${postgres_port}" --dbname="${postgres_database}" --username="${postgres_username}" --tuples-only --no-align --command='SELECT 1' 2>/dev/null)"; then
  [ "${psql_result}" != "1" ] && echo "❌ psql returned '${psql_result}' for SELECT 1" >&2 && exit 1
else
  psql --help=commands >"${tmp}/psql-commands.txt"
  rg -Fq '\c[onnect]' "${tmp}/psql-commands.txt"
fi

rg --version >/dev/null
rg -Fxq '# Diene Go consumer' README.md

sg --version >/dev/null
printf '%s\n' '[general]' 'contrib=CT1' 'ignore=B6' '' '[contrib-title-conventional-commits]' 'types = amend' >"${tmp}/.gitlint"
yq '.gitlint = ".gitlint"' atomi_release.yaml >"${tmp}/sg-config.yaml"
(cd "${tmp}" && sg gitlint -c sg-config.yaml >/dev/null 2>&1 || true)
rg -q 'chore' "${tmp}/.gitlint"

shellcheck --version >/dev/null
shellcheck scripts/validate/binary-smoke.sh

skopeo --version >/dev/null
printf '%s\n' '{"schemaVersion":2,"mediaType":"application/vnd.oci.image.manifest.v1+json","config":{"mediaType":"application/vnd.oci.image.config.v1+json","digest":"sha256:44136fa355b3678a1146ad16f7e8649e94fb4fc21fe77e8310c060f61caaff8a","size":2},"layers":[]}' >"${tmp}/manifest.json"
skopeo manifest-digest "${tmp}/manifest.json" | rg -q '^sha256:[0-9a-f]{64}$'

task --version >/dev/null
task --list >/dev/null

treefmt --version >/dev/null
treefmt --completion bash >"${tmp}/treefmt-completion.bash"
[ ! -s "${tmp}/treefmt-completion.bash" ] && echo "❌ treefmt completion generation failed" >&2 && exit 1

yq --version >/dev/null
yq -en '.ok = true | .ok == true' >/dev/null

if command -v releaser >/dev/null; then
  releaser --help >/dev/null
else
  echo "⏭️ releaser binary awaits the workspace-level package publish"
fi

# ### workspace-complete
# #### source: workspace
echo "✅ Binary smoke passed"
