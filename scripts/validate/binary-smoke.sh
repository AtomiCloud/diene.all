#!/usr/bin/env bash
set -euo pipefail

for binary in actionlint bash cyanprint docker git gomplate hadolint helm helm-docs infisical jq k3d kubeconform kubectl kyverno nix pre-commit releaser rg shellcheck skopeo task treefmt yq; do
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
cyanprint cache inspect --cache-dir "${tmp}/cyanprint-cache" --json |
  jq -e '.status == "done" and .action == "inspect"' >/dev/null

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
helm template diene-workspace infra/root_chart | kubeconform -strict -summary >/dev/null

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

pre-commit --version >/dev/null
pre-commit validate-config .pre-commit-config.yaml

releaser --version >/dev/null
# Exercised against the REAL `atomi_release.yaml`, because loading that file is what
# the binary does before it can lint anything: a `lint-commit` run that reaches a
# verdict has also parsed and schema-validated the release configuration, which is
# the only validation this repository has now that the standalone config validator
# is deleted.
printf '%s\n' 'chore: smoke the releaser commit linter' >"${tmp}/releaser-msg-ok.txt"
releaser lint-commit "${tmp}/releaser-msg-ok.txt" -c atomi_release.yaml >/dev/null
# The negative direction, so a linter that accepted everything would not pass as a
# working one. `nope` is not a configured type. `if !` rather than `cmd && { … }`:
# the correct outcome here is a non-zero exit, which under errexit would kill the
# script if it were the status of a list.
printf '%s\n' 'nope: this commit type is not configured' >"${tmp}/releaser-msg-bad.txt"
if releaser lint-commit "${tmp}/releaser-msg-bad.txt" -c atomi_release.yaml >/dev/null 2>&1; then
  echo "❌ releaser lint-commit accepted a commit type that is not in atomi_release.yaml" >&2
  exit 1
fi

rg --version >/dev/null
# Smoke-tested against a fixture this script writes, like every other binary here —
# actionlint gets its own workflow, git its own repo, jq `-en`, releaser its own
# commit-message file.
# This line used to read `rg -q 'Diene workspace baseline' README.md`, which was the
# ONLY assertion against a tracked PROSE file anywhere in scripts/ or probes/, and
# the string existed nowhere else in the tree — so it was never a content contract,
# just a convenient needle. Composing README.md dropped the string, every baseline
# arm went `broken`, and a whole venue matrix was voided by a smoke test that was
# never about the README. A tool check must not depend on documentation wording.
printf '%s\n' 'alpha' 'ripgrep smoke needle' 'omega' >"${tmp}/rg-fixture.txt"
rg -q 'ripgrep smoke needle' "${tmp}/rg-fixture.txt"
# `cmd && { …; exit 1; }` would be wrong here: when rg correctly finds nothing it
# exits 1, that becomes the list's status, and `set -e` kills the script on the
# CORRECT outcome. `if !` is the form that survives errexit.
if ! rg -q 'no-such-needle-should-ever-match' "${tmp}/rg-fixture.txt"; then
  : # expected: rg found nothing, which is the point of the negative arm
else
  echo "❌ rg reported a match for a pattern that is not in the fixture" >&2
  exit 1
fi

shellcheck --version >/dev/null
shellcheck scripts/validate/binary-smoke.sh

skopeo --version >/dev/null
printf '%s\n' '{"schemaVersion":2,"mediaType":"application/vnd.oci.image.manifest.v1+json","config":{"mediaType":"application/vnd.oci.image.config.v1+json","digest":"sha256:44136fa355b3678a1146ad16f7e8649e94fb4fc21fe77e8310c060f61caaff8a","size":2},"layers":[]}' >"${tmp}/manifest.json"
skopeo manifest-digest "${tmp}/manifest.json" | rg -q '^sha256:[0-9a-f]{64}$'

task --version >/dev/null
task --list >/dev/null
# `task` (go-task) is the ONE task runner. `pls` was removed by owner ruling: it
# was not a second program but a second NAME for this one - both reported
# version 3.48.0 and both read the same Taskfile.yaml / tasks/Taskfile.*.yaml set.
#
# This is a text assertion on the declaration, not a `command -v pls` check. The
# dev shell inherits the caller's PATH, so a `pls` the developer installed for
# their own unrelated reasons would turn a PATH check red for a fault this
# repository does not have. What must not come back is the DECLARATION.
if rg -q '\bpls\b' nix/packages.nix nix/env.nix; then
  echo "❌ pls is back in the nix inventory - by owner ruling, task (go-task) is the only task runner" >&2
  exit 1
fi

# Same shape, same reason, different binary: `sg` was the temporary gitlint
# bootstrap this toolchain carried only while the releaser was unavailable HERE.
# The releaser is now declared and smoke-tested above, so `sg` has no remaining
# job, and its DECLARATION is what must not come back - a developer with their own
# `sg` on PATH is not a fault of this repository, so this is a text assertion and
# not `command -v sg`.
if rg -q '\bsg\b' nix/packages.nix nix/env.nix; then
  echo "❌ sg is back in the nix inventory - the releaser replaced it, there is no gitlint bootstrap" >&2
  exit 1
fi

treefmt --version >/dev/null
treefmt --completion bash >"${tmp}/treefmt-completion.bash"
[ ! -s "${tmp}/treefmt-completion.bash" ] && echo "❌ treefmt completion generation failed" >&2 && exit 1

yq --version >/dev/null
yq -en '.ok = true | .ok == true' >/dev/null

echo "✅ Binary smoke passed"
