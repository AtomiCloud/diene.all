#!/usr/bin/env bash
set -euo pipefail

for binary in actionlint bash dn-inspect docker dotnet dotnetlint git gitlint gomplate hadolint helm helm-docs infisical jq k3d kubeconform kubectl kyverno nix pls pre-commit rg sg shellcheck skopeo task treefmt yq; do
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

docker --version >/dev/null
docker info --format '{{.ServerVersion}}' >/dev/null

dn-inspect --version >/dev/null
dotnet tool restore >/dev/null
mkdir -p "${tmp}/dotnet-smoke"
printf '%s\n' '<Project Sdk="Microsoft.NET.Sdk">' '  <PropertyGroup>' '    <OutputType>Exe</OutputType>' '    <TargetFramework>net10.0</TargetFramework>' '    <ImplicitUsings>enable</ImplicitUsings>' '  </PropertyGroup>' '</Project>' >"${tmp}/dotnet-smoke/Smoke.csproj"
printf '%s\n' 'Console.WriteLine("smoke");' >"${tmp}/dotnet-smoke/Program.cs"
dotnet restore "${tmp}/dotnet-smoke/Smoke.csproj" >/dev/null
dn-inspect --projects "${tmp}/dotnet-smoke/Smoke.csproj" --filter '^$' | rg -q 'Total: 0 issue\(s\)'

dotnet --version >/dev/null
dotnet sln dotnet-base.slnx list | rg -q 'App/App.csproj'

dotnetlint --version >/dev/null
(cd "${tmp}/dotnet-smoke" && dotnetlint) | rg -q 'Processing project:'

git --version >/dev/null
git rev-parse --is-inside-work-tree >/dev/null

gitlint --version >/dev/null
printf '%s\n' 'feat: binary smoke' >"${tmp}/commit-message"
gitlint --msg-filename "${tmp}/commit-message"

gomplate --version >/dev/null
[ "$(gomplate -i '{{ add 1 1 }}')" != "2" ] && echo "❌ gomplate failed a real template" >&2 && exit 1

hadolint --version >/dev/null

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
rg -q 'Diene .NET base template' README.md

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
  echo "⏭️ releaser binary awaits the C2 step-2p tools/releaser publish"
fi

echo "✅ Binary smoke passed"
