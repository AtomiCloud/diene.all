#!/usr/bin/env bash
set -euo pipefail

# ### workspace
# #### source: workspace
# bun-consumer keeps the package.json-aware form: this node installs a JS
# toolchain, so the binary set is not fixed. `sg` is taken from workspace;
# `releaser` moved out of the array into the conditional check below, because
# workspace establishes it may legitimately be absent before the C2 publish.
if [ -f package.json ]; then
  ./scripts/local/setup.sh
  export PATH="${PWD}/node_modules/.bin:${PATH}"
fi

binaries=(actionlint bash cyanprint docker git gomplate hadolint helm helm-docs infisical jq k3d kubeconform kubectl kyverno nix pls pre-commit rg sg shellcheck skopeo task treefmt yq)
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

mapfile -t cyanprint_versions < <(
  awk -F'"' '/^[[:space:]]*cyanprintVersion = "[^"]+";$/ { print $2 }' nix/packages.nix
)
if [ "${#cyanprint_versions[@]}" -ne 1 ]; then
  echo "expected exactly one cyanprintVersion pin in nix/packages.nix" >&2
  exit 1
fi
cyanprint --version | grep -Fqx "cyanprint ${cyanprint_versions[0]}"

mkdir -p "${tmp}/cyanprint-cache"
cyanprint cache inspect --cache-dir "${tmp}/cyanprint-cache" --json | jq -e '.status == "done" and .action == "inspect"' >/dev/null

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

docker --version >/dev/null
docker info --format '{{.ServerVersion}}' >/dev/null

git --version >/dev/null
git rev-parse --is-inside-work-tree >/dev/null

gomplate --version >/dev/null
[ "$(gomplate -i '{{ add 1 1 }}')" != "2" ] && echo "❌ gomplate failed a real template" >&2 && exit 1

hadolint --version >/dev/null
hadolint infra/Dockerfile

helm-docs --version >/dev/null
helm-docs --dry-run --chart-search-root infra/root_chart >/dev/null 2>&1

helm version --short >/dev/null
helm template diene-workspace infra/root_chart | kubeconform -strict -summary -ignore-missing-schemas >/dev/null

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

rg --version >/dev/null
rg -q '^## Bun foundation$|^# Diene workspace baseline$' README.md

releaser --version | rg -qx '1.0.0'
printf '%s\n' 'feat: add a smoke capability' >"${tmp}/good-commit.txt"
releaser lint-commit -c atomi_release.yaml "${tmp}/good-commit.txt"
printf '%s\n' 'wibble: not a real type' >"${tmp}/bad-commit.txt"
releaser lint-commit -c atomi_release.yaml "${tmp}/bad-commit.txt" && {
  echo "❌ releaser lint-commit accepted an invalid commit" >&2
  exit 1
}

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
  echo "⏭️ releaser binary awaits the C2 step-2p tools/releaser publish"
fi

# ### workspace-complete
# #### source: workspace
echo "✅ Binary smoke passed"
