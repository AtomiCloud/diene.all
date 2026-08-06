import { expectGreen, expectRedBecause } from './lib/helpers.ts';

const declarationFiles = 'nix/packages.nix nix/env.nix';

// Text assertion on the declaration, not `command -v`: the shell inherits caller PATH.
const retired = [
  { binary: 'pls', reason: 'task (go-task) is the only task runner' },
  { binary: 'sg', reason: 'the releaser replaced it, there is no gitlint bootstrap' },
];

const absenceCommand = (binary: string) =>
  `nix develop .#default -c bash -c 'if rg -q "\\b${binary}\\b" ${declarationFiles}; then echo "${binary} is back in the nix inventory" >&2; exit 1; fi; echo "${binary} is absent from the nix inventory"'`;

// This is a JS template literal, not raw shell. String.raw suppresses ESCAPE
// processing only; it does not suppress interpolation, so a ${...} below is read by
// JS and never reaches the shell. Shell variables are written bare ($var) for that
// reason. probes/lib/probe-modules.test.ts imports every probe module, which is what
// makes this checkable: a ${...} naming no JS binding throws at module scope.
const invocations = String.raw`
set -euo pipefail
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

actionlint -version >/dev/null
printf '%s\n' 'name: Smoke' 'on: push' 'jobs:' '  smoke:' '    runs-on: ubuntu-latest' '    steps:' '      - run: echo smoke' >"$tmp/workflow.yaml"
actionlint "$tmp/workflow.yaml"

bash --version >/dev/null
[ "$(bash -c 'printf smoke')" != "smoke" ] && echo "bash failed a real invocation" >&2 && exit 1

# The version is the registry's, so there is no pin in this tree to compare against.
# The store path the shell resolved is the declaration's own answer: it carries the
# derivation name, so a version the binary reports that the resolved derivation does
# not carry is caught here rather than reported as agreement with itself.
cyanprint_version="$(cyanprint --version | awk '{ print $2 }')"
[ -n "$cyanprint_version" ] || { echo "cyanprint --version printed no version" >&2; exit 1; }
cyanprint_path="$(command -v cyanprint)"
printf '%s\n' "$cyanprint_path" | rg -q "/nix/store/[^/]*-cyanprint-$cyanprint_version/" || {
  echo "cyanprint reports $cyanprint_version but resolved to $cyanprint_path" >&2
  exit 1
}
cyanprint cache inspect --cache-dir "$tmp/cyanprint-cache" --json |
  jq -e '.status == "done" and .action == "inspect"' >/dev/null

dlint exec-bits >/dev/null

docker --version >/dev/null
docker info --format '{{.ServerVersion}}' >/dev/null

git --version >/dev/null
git rev-parse --is-inside-work-tree >/dev/null

gomplate --version >/dev/null
[ "$(gomplate -i '{{ add 1 1 }}')" != "2" ] && echo "gomplate failed a real template" >&2 && exit 1

hadolint --version >/dev/null
hadolint infra/Dockerfile

helm-docs --version >/dev/null
helm-docs --dry-run --chart-search-root infra/root_chart >/dev/null 2>&1

helm version --short >/dev/null
helm template diene-workspace infra/root_chart | kubeconform -strict -summary >/dev/null

infisical --version >/dev/null
git -C "$tmp" init -q
git -C "$tmp" config user.email smoke@example.invalid
git -C "$tmp" config user.name Smoke
touch "$tmp/empty"
git -C "$tmp" add empty
git -C "$tmp" commit -qm smoke
(cd "$tmp" && infisical scan . -v >/dev/null 2>&1)

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
printf '%s\n' 'chore: smoke the releaser commit linter' >"$tmp/releaser-msg-ok.txt"
releaser lint-commit "$tmp/releaser-msg-ok.txt" -c atomi_release.yaml >/dev/null
printf '%s\n' 'nope: this commit type is not configured' >"$tmp/releaser-msg-bad.txt"
if releaser lint-commit "$tmp/releaser-msg-bad.txt" -c atomi_release.yaml >/dev/null 2>&1; then
  echo "releaser lint-commit accepted a commit type that is not in atomi_release.yaml" >&2
  exit 1
fi

rg --version >/dev/null
printf '%s\n' 'alpha' 'ripgrep smoke needle' 'omega' >"$tmp/rg-fixture.txt"
rg -q 'ripgrep smoke needle' "$tmp/rg-fixture.txt"
# rg exits 1 for no-match and 2 for error, so only the exact code proves the fixture was read.
rc=0
rg -q 'no-such-needle-should-ever-match' "$tmp/rg-fixture.txt" || rc=$?
[ "$rc" = "1" ] || { echo "rg: expected exit 1 (no match), got $rc" >&2; exit 1; }

shellcheck --version >/dev/null
printf '%s\n' '#!/usr/bin/env bash' 'set -euo pipefail' 'echo "shellcheck smoke"' >"$tmp/shellcheck-clean.sh"
shellcheck "$tmp/shellcheck-clean.sh"
# A clean file exits 0 and so does a shellcheck that inspected nothing, so the green above
# carries no evidence on its own. shellcheck exits 1 for a finding and 2 for a file it could
# not read: only the exact code, plus the code of the finding itself, proves the fixture was
# read. Same reasoning as the rg fixture above.
printf '%s\n' '#!/usr/bin/env bash' 'set -euo pipefail' 'echo $UNQUOTED' >"$tmp/shellcheck-finding.sh"
rc=0
shellcheck "$tmp/shellcheck-finding.sh" >"$tmp/shellcheck-out.txt" 2>&1 || rc=$?
[ "$rc" = "1" ] || { echo "shellcheck: expected exit 1 (finding), got $rc" >&2; exit 1; }
rg -q 'SC2086' "$tmp/shellcheck-out.txt" || { echo "shellcheck: exit 1 without the SC2086 finding" >&2; exit 1; }

skopeo --version >/dev/null
printf '%s\n' '{"schemaVersion":2,"mediaType":"application/vnd.oci.image.manifest.v1+json","config":{"mediaType":"application/vnd.oci.image.config.v1+json","digest":"sha256:44136fa355b3678a1146ad16f7e8649e94fb4fc21fe77e8310c060f61caaff8a","size":2},"layers":[]}' >"$tmp/manifest.json"
skopeo manifest-digest "$tmp/manifest.json" | rg -q '^sha256:[0-9a-f]{64}$'

task --version >/dev/null
task --list >/dev/null

treefmt --version >/dev/null
treefmt --completion bash >"$tmp/treefmt-completion.bash"
[ ! -s "$tmp/treefmt-completion.bash" ] && echo "treefmt completion generation failed" >&2 && exit 1

yq --version >/dev/null
yq -en '.ok = true | .ok == true' >/dev/null

echo "toolchain invocations passed"
`;

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-binary-smoke-resolves',
      description: 'Every binary the workspace declares for the default shell resolves in it.',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(repo, 'nix develop .#default -c dlint toolchain-smoke', 'binary-smoke');
      },
    },
    {
      name: 'baseline-binary-smoke-invokes',
      description: 'Every declared workspace binary answers a real smoke invocation, not just a PATH lookup.',
      kind: 'baseline',
      async run(repo: any) {
        await repo.write('probe-toolchain-invocations.sh', invocations);
        try {
          await expectGreen(repo, 'nix develop .#default -c bash probe-toolchain-invocations.sh', 'binary-smoke');
        } finally {
          await repo.exec('rm -f probe-toolchain-invocations.sh');
        }
      },
    },
    ...retired.flatMap(({ binary, reason }) => [
      {
        name: `baseline-binary-smoke-${binary}-absent`,
        description: `${binary} is not declared in the nix inventory: ${reason}.`,
        kind: 'baseline' as const,
        async run(repo: any) {
          await expectGreen(repo, absenceCommand(binary), 'binary-smoke');
        },
      },
      {
        name: `mutation-binary-smoke-${binary}-redeclared-caught`,
        description: `Re-declaring ${binary} in the nix inventory must turn the absence assertion red.`,
        kind: 'mutation' as const,
        expectedImpact: [],
        // Injected into the package set, not into an env group: an env group naming a
        // package the set does not carry breaks `nix develop` at EVALUATION, so the
        // arm would go red without ever reaching the assertion.
        async run(repo: any) {
          const source = await repo.read('nix/packages.nix');
          const anchor = '          atomiutils\n';
          if (!source.includes(anchor)) {
            throw new Error(`could not find the registry inherit anchor in nix/packages.nix`);
          }
          await repo.write('nix/packages.nix', source.replace(anchor, `${anchor}          ${binary}\n`));
          await expectRedBecause(repo, absenceCommand(binary), 'binary-smoke', [
            `${binary} is back in the nix inventory`,
          ]);
        },
      },
    ]),
  ],
};
