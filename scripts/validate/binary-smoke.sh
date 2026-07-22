#!/usr/bin/env bash
set -euo pipefail

if [ -f package.json ]; then
  ./scripts/local/setup.sh
  export PATH="${PWD}/node_modules/.bin:${PATH}"
fi

binaries=(actionlint bash dpkg gh git go goreleaser helm helm-docs infisical jq kubeconform kubectl kyverno nix pls pre-commit releaser rg rpm shellcheck task treefmt yq)
[ -f package.json ] && binaries+=(bun biome knip tsc)

for binary in "${binaries[@]}"; do
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

if [ -f package.json ]; then
  bun --version >/dev/null
  [ "$(bun -e 'process.stdout.write(String(1 + 1))')" != "2" ] && echo "❌ bun failed a real invocation" >&2 && exit 1

  biome --version >/dev/null
  mkdir -p "${tmp}/biome"
  printf '%s\n' \
    '{' \
    '  "vcs": {"enabled": false},' \
    '  "formatter": {"enabled": false},' \
    '  "linter": {"enabled": true, "rules": {"recommended": true}}' \
    '}' >"${tmp}/biome/biome.json"
  printf '%s\n' 'export const smoke = 1;' >"${tmp}/biome/smoke.ts"
  biome lint --config-path="${tmp}/biome/biome.json" "${tmp}/biome/smoke.ts" >/dev/null

  knip --version >/dev/null
  mkdir -p "${tmp}/knip/src"
  printf '%s\n' '{"name":"binary-smoke","private":true,"type":"module"}' >"${tmp}/knip/package.json"
  printf '%s\n' '{"entry":["src/index.ts"],"project":["src/**/*.ts"]}' >"${tmp}/knip/knip.json"
  printf '%s\n' 'export const smoke = 1;' >"${tmp}/knip/src/index.ts"
  knip --directory "${tmp}/knip" --config knip.json >/dev/null

  tsc --version >/dev/null
  mkdir -p "${tmp}/tsc"
  printf '%s\n' '{"compilerOptions":{"strict":true,"noEmit":true},"files":["smoke.ts"]}' >"${tmp}/tsc/tsconfig.json"
  printf '%s\n' 'const smoke: number = 1;' 'void smoke;' >"${tmp}/tsc/smoke.ts"
  tsc --project "${tmp}/tsc/tsconfig.json"
fi

dpkg --version >/dev/null
dpkg --print-architecture >/dev/null

gh --version >/dev/null
gh help >/dev/null

git --version >/dev/null
git rev-parse --is-inside-work-tree >/dev/null

go version >/dev/null
go env GOOS >/dev/null

goreleaser --version >/dev/null
goreleaser check >/dev/null

helm-docs --version >/dev/null

helm version --short >/dev/null

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

rg --version >/dev/null
rg -q '^# Releaser$' README.md

rpm --version >/dev/null
rpm --eval '%{_arch}' >/dev/null

shellcheck --version >/dev/null
shellcheck scripts/validate/binary-smoke.sh

task --version >/dev/null
task --list >/dev/null

treefmt --version >/dev/null
treefmt --completion bash >"${tmp}/treefmt-completion.bash"
[ ! -s "${tmp}/treefmt-completion.bash" ] && echo "❌ treefmt completion generation failed" >&2 && exit 1

yq --version >/dev/null
yq -en '.ok = true | .ok == true' >/dev/null

releaser --help >/dev/null

echo "✅ Binary smoke passed"
