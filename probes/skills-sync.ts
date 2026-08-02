import { expectGreen, withCleanProbeState } from './lib/helpers.ts';

const externalGoModule = 'github.com/AtomiCloud/diene.go-fixture';
const goModFixture = `module example.com/app\n\ngo 1.22\n\nrequire ${externalGoModule} v0.1.0\n`;
const neutralGoModFixture = 'module example.com/no-diene-dependencies\n\ngo 1.22\n';
const goSelfModuleFixture = 'module diene.example.com/go-base\n\ngo 1.22\n';

const externalGoShim = [
  '#!/usr/bin/env bash',
  'case "$*" in',
  '  "mod edit -json")',
  `    printf '{"Module":{"Path":"example.com/app"},"Go":"1.22","Require":[{"Path":"${externalGoModule}","Version":"v0.1.0"}]}\\n'`,
  '    ;;',
  '  "list -m -json all")',
  '    printf \'{"Path":"example.com/app","Main":true,"Dir":"%s"}\\n\' "$PWD"',
  `    printf '{"Path":"${externalGoModule}","Version":"v0.1.0","Dir":"%s/go-fixture"}\\n' "$PWD"`,
  '    ;;',
  '  *)',
  '    echo "unexpected fake-go invocation: $*" >&2',
  '    exit 97',
  '    ;;',
  'esac',
  '',
].join('\n');

const neutralGoShim = [
  '#!/usr/bin/env bash',
  'case "$*" in',
  '  "mod edit -json")',
  '    printf \'{"Module":{"Path":"example.com/no-diene-dependencies"},"Go":"1.22"}\\n\'',
  '    ;;',
  '  "list -m -json all")',
  '    printf \'{"Path":"example.com/no-diene-dependencies","Main":true,"Dir":"%s"}\\n\' "$PWD"',
  '    ;;',
  '  *)',
  '    echo "unexpected fake-go invocation: $*" >&2',
  '    exit 97',
  '    ;;',
  'esac',
  '',
].join('\n');

const selfModuleGoShim = [
  '#!/usr/bin/env bash',
  'case "$*" in',
  '  "mod edit -json")',
  '    printf \'{"Module":{"Path":"diene.example.com/go-base"},"Go":"1.22"}\\n\'',
  '    ;;',
  '  "list -m -json all")',
  '    printf \'{"Path":"diene.example.com/go-base","Main":true,"Dir":"%s"}\\n\' "$PWD"',
  '    ;;',
  '  *)',
  '    echo "unexpected fake-go invocation: $*" >&2',
  '    exit 97',
  '    ;;',
  'esac',
  '',
].join('\n');

const brokenGoShim = [
  '#!/usr/bin/env bash',
  '# `go mod edit -json` succeeds so the declaration is detected; the module',
  '# listing fails the way an unreachable proxy fails.',
  'if [ "$1" = "mod" ] && [ "$2" = "edit" ]; then',
  '  printf \'{"Module":{"Path":"example.com/app"},"Require":[{"Path":"diene.example.com/go-core","Version":"v0.1.0"}]}\\n\'',
  '  exit 0',
  'fi',
  'echo "go: diene.example.com/go-core: proxy unreachable" >&2',
  'exit 1',
  '',
].join('\n');

// The root go.mod requires one matching module that never resolves, while the
// module graph carries an unrelated matching module transitively. Only the
// listed transitive module ships skills, so a resolver that reads any matching
// module in the graph as "the declaration resolved" publishes a tree missing the
// module that was actually required.
const directGoModule = 'github.com/AtomiCloud/diene.direct';
const transitiveGoModule = 'github.com/vendor/diene.transitive';
const transitiveGoModFixture = `module example.com/app\n\ngo 1.22\n\nrequire ${directGoModule} v0.1.0\n`;
const transitiveGoShim = [
  '#!/usr/bin/env bash',
  'case "$*" in',
  '  "mod edit -json")',
  `    printf '{"Module":{"Path":"example.com/app"},"Go":"1.22","Require":[{"Path":"${directGoModule}","Version":"v0.1.0"}]}\\n'`,
  '    ;;',
  '  "list -m -json all")',
  '    printf \'{"Path":"example.com/app","Main":true,"Dir":"%s"}\\n\' "$PWD"',
  `    printf '{"Path":"${transitiveGoModule}","Version":"v0.2.0","Dir":"%s/go-fixture"}\\n' "$PWD"`,
  '    ;;',
  '  *)',
  '    echo "unexpected fake-go invocation: $*" >&2',
  '    exit 97',
  '    ;;',
  'esac',
  '',
].join('\n');

// The root go.mod directly requires two matching modules. Only one of them is
// reachable in the module graph, so a resolver that answers for the ecosystem as
// a whole reads the module that DID resolve as proof that both did, and publishes
// a tree missing the skills of the module that never appeared.
const resolvedGoModule = 'github.com/AtomiCloud/diene.resolved';
const unresolvedGoModule = 'github.com/AtomiCloud/diene.unresolved';
const partialGoModFixture = `module example.com/app\n\ngo 1.22\n\nrequire (\n\t${resolvedGoModule} v0.1.0\n\t${unresolvedGoModule} v0.1.0\n)\n`;
const partialGoShim = [
  '#!/usr/bin/env bash',
  'case "$*" in',
  '  "mod edit -json")',
  `    printf '{"Module":{"Path":"example.com/app"},"Go":"1.22","Require":[{"Path":"${resolvedGoModule}","Version":"v0.1.0"},{"Path":"${unresolvedGoModule}","Version":"v0.1.0"}]}\\n'`,
  '    ;;',
  '  "list -m -json all")',
  '    printf \'{"Path":"example.com/app","Main":true,"Dir":"%s"}\\n\' "$PWD"',
  `    printf '{"Path":"${resolvedGoModule}","Version":"v0.1.0","Dir":"%s/go-fixture"}\\n' "$PWD"`,
  '    ;;',
  '  *)',
  '    echo "unexpected fake-go invocation: $*" >&2',
  '    exit 97',
  '    ;;',
  'esac',
  '',
].join('\n');

const declaringPubspec = [
  'name: skills_sync_fixture',
  'environment:',
  "  sdk: '>=3.0.0 <4.0.0'",
  'dependencies:',
  '  diene_absent: ^1.0.0',
  '  http: ^1.0.0',
  '',
].join('\n');

const malformedPackageJson = '{ "dependencies": {\n';
const malformedPackageConfig = '{ "configVersion": 2, "packages": [\n';

const declaringPackageJson = `${JSON.stringify(
  {
    name: 'skills-sync-fixture',
    private: true,
    dependencies: { '@atomicloud/diene.absent': '1.0.0' },
  },
  null,
  2,
)}\n`;

const vendorDir = '.claude/skills/vendor';
const keptSkill = `${vendorDir}/diene.kept/example/SKILL.md`;
const probeCleanTargets = [
  vendorDir,
  'node_modules/@atomicloud/diene.readonly',
  'node_modules/@atomicloud/diene.untracked',
  'package.json',
  'go.mod',
  'go-fixture',
  'go-shim',
  'pubspec.yaml',
  '.dart_tool',
];

async function stageKeptSkill(repo: any): Promise<void> {
  await repo.write(keptSkill, 'committed skill\n');
  const staged = await repo.exec(`git add ${keptSkill}`);
  if (staged.exitCode !== 0) {
    throw new Error(`could not stage the committed vendored skill: ${staged.stderr || staged.stdout}`);
  }
}

async function removeCommittedVendor(repo: any): Promise<void> {
  const removed = await repo.exec(`git rm -rf -- ${vendorDir}`);
  if (removed.exitCode !== 0) {
    throw new Error(
      `could not remove committed vendored skills from an empty-world fixture: ${removed.stderr || removed.stdout}`,
    );
  }
}

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-skills-sync-green',
      description:
        'The universal skills synchronizer vendors read-only package content, self-cleans, records a deterministic manifest, and is idempotent on its second run.',
      kind: 'baseline',
      async run(repo: any) {
        await withCleanProbeState(repo, probeCleanTargets, async () => {
          await repo.write('go.mod', goModFixture);
          await repo.write('go-shim/go', externalGoShim);
          await repo.write('go-fixture/skills/example/SKILL.md', 'external Go skill\n');
          await repo.write('.claude/skills/vendor/stale/SKILL.md', 'stale\n');
          await expectGreen(
            repo,
            `nix develop .#ci -c bash -c 'set -euo pipefail; first="$(mktemp -d)"; second="$(mktemp -d)"; readonly_skill="node_modules/@atomicloud/diene.readonly/skills/example"; trap "rm -rf \\"$first\\" \\"$second\\"" EXIT; chmod +x go-shim/go; export PATH="$PWD/go-shim:$PATH"; mkdir -p "$readonly_skill"; printf "readonly skill\\n" >"$readonly_skill/SKILL.md"; chmod -R a-w node_modules/@atomicloud/diene.readonly .claude/skills/vendor/stale; ./scripts/local/skills-sync.sh; test ! -e .claude/skills/vendor/stale; test -f .claude/skills/vendor/diene.readonly/example/SKILL.md; test -f .claude/skills/vendor/diene.go-fixture/example/SKILL.md; test "$(cat .claude/skills/vendor/diene.readonly/example/SKILL.md)" = "readonly skill"; test "$(cat .claude/skills/vendor/diene.go-fixture/example/SKILL.md)" = "external Go skill"; jq -e "(index(\\"diene.go-fixture/example/SKILL.md\\") != null) and (index(\\"diene.readonly/example/SKILL.md\\") != null) and ([.[] | select(startswith(\\"diene.go-fixture/\\") or startswith(\\"diene.readonly/\\") or startswith(\\"diene.untracked/\\"))] | length == 2)" .claude/skills/vendor/manifest.json >/dev/null; cp -R .claude/skills/vendor/. "$first"/; ./scripts/local/skills-sync.sh; cp -R .claude/skills/vendor/. "$second"/; diff -ru "$first" "$second"'`,
            'skills-sync',
          );
        });
      },
    },
    {
      name: 'baseline-skills-sync-cold-preserve-green',
      description:
        'A declared but unresolved cold checkout keeps the committed vendored skills byte-for-byte instead of emptying them.',
      kind: 'baseline',
      async run(repo: any) {
        await withCleanProbeState(repo, probeCleanTargets, async () => {
          await repo.write('package.json', declaringPackageJson);
          await repo.write('go.mod', neutralGoModFixture);
          await repo.write('go-shim/go', neutralGoShim);
          await stageKeptSkill(repo);
          await expectGreen(
            repo,
            `nix develop .#ci -c bash -c 'set -euo pipefail; chmod +x go-shim/go; export PATH="$PWD/go-shim:$PATH"; iso="$(mktemp -d)"; trap "if [ -d \\"$iso/@atomicloud\\" ]; then rm -rf node_modules/@atomicloud; mkdir -p node_modules; mv \\"$iso/@atomicloud\\" node_modules/; fi; rm -rf \\"$iso\\"" EXIT; if [ -d node_modules/@atomicloud ]; then mv node_modules/@atomicloud "$iso/"; fi; mkdir -p node_modules; ./scripts/local/skills-sync.sh; test "$(cat ${keptSkill})" = "committed skill"'`,
            'skills-sync',
          );
        });
      },
    },
    {
      name: 'baseline-skills-sync-missing-go-refusal',
      description:
        'A diene-requiring go.mod without a go toolchain refuses with an actionable diagnostic instead of a bare command-not-found.',
      kind: 'baseline',
      async run(repo: any) {
        await withCleanProbeState(repo, probeCleanTargets, async () => {
          await repo.write('go.mod', goModFixture);
          // Build an explicit utility PATH without Go. This keeps the fixture
          // valid after the parent probe cascades into Go-enabled nodes, even if
          // an ambient PATH directory happens to contain Go beside other tools.
          const result = await repo.exec(
            `nix develop .#ci -c bash -c 'set -euo pipefail; fixture_bin="$(mktemp -d)"; trap "rm -rf \\"$fixture_bin\\"" EXIT; for command_name in bash env jq rg sed mktemp touch mkdir cp chmod rm mv find tr basename realpath git dirname sort wc head grep cat cut awk; do command_path="$(command -v "$command_name")" || exit 112; ln -s "$command_path" "$fixture_bin/$command_name"; done; export PATH="$fixture_bin"; if command -v go >/dev/null 2>&1; then exit 111; fi; ./scripts/local/skills-sync.sh'`,
            { timeoutMs: 240000 },
          );
          if (result.exitCode === 111) {
            throw new Error('the explicit no-Go fixture PATH unexpectedly resolves go');
          }
          if (result.exitCode === 112) {
            throw new Error('the .#ci shell is missing a utility required to construct the no-Go fixture');
          }
          if (result.exitCode === 0) {
            throw new Error('skills-sync succeeded with a diene-requiring go.mod and no go toolchain');
          }
          const output = `${result.stdout}\n${result.stderr}`;
          if (!output.includes('go.mod is present but the go toolchain is not on PATH')) {
            throw new Error(`skills-sync did not report the missing go toolchain:\n${output}`);
          }
        });
      },
    },
    {
      name: 'baseline-skills-sync-go-self-empty-green',
      description:
        'A Diene-named Go main module with no external Diene requirements and no local skills is legitimately empty.',
      kind: 'baseline',
      async run(repo: any) {
        await withCleanProbeState(repo, probeCleanTargets, async () => {
          await removeCommittedVendor(repo);
          await repo.write('go.mod', goSelfModuleFixture);
          await repo.write('go-shim/go', selfModuleGoShim);
          await expectGreen(
            repo,
            `nix develop .#ci -c bash -c 'set -euo pipefail; chmod +x go-shim/go; export PATH="$PWD/go-shim:$PATH"; ./scripts/local/skills-sync.sh; jq -e "[.[] | select(startswith(\\"diene.go-fixture/\\") or startswith(\\"diene.readonly/\\") or startswith(\\"diene.untracked/\\"))] | length == 0" .claude/skills/vendor/manifest.json >/dev/null'`,
            'skills-sync',
          );
        });
      },
    },
    {
      name: 'mutation-skills-sync-broken-go-caught',
      description:
        'A focused sabotage must turn the skills-sync mechanism red: a failing go module listing must fail the sync outright, even with committed vendored skills that could have been preserved.',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: any) {
        await withCleanProbeState(repo, probeCleanTargets, async () => {
          await repo.write('go.mod', goModFixture);
          await repo.write('go-shim/go', brokenGoShim);
          await stageKeptSkill(repo);
          const result = await repo.exec(
            `nix develop .#ci -c bash -c 'set -euo pipefail; chmod +x go-shim/go; export PATH="$PWD/go-shim:$PATH"; ./scripts/local/skills-sync.sh'`,
            { timeoutMs: 240000 },
          );
          if (result.exitCode === 0) {
            throw new Error('skills-sync stayed green after the Go module listing failed');
          }
          const output = `${result.stdout}\n${result.stderr}`;
          if (!output.includes('Failed to list Go modules (go list -m -json all)')) {
            throw new Error(`skills-sync failed for the wrong reason after the broken Go resolver:\n${output}`);
          }
        });
      },
    },
    {
      name: 'mutation-skills-sync-go-self-false-positive-caught',
      description:
        'A focused sabotage must turn the self-module baseline red: treating the main module as an external obligation rejects a legitimate empty result.',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: any) {
        await withCleanProbeState(repo, probeCleanTargets, async () => {
          await removeCommittedVendor(repo);
          const declarationSite = '  if [ -s "${go_required}" ]; then\n    go_declared=true\n  fi\n';
          await repo.patch('scripts/local/skills-sync.sh', {
            find: declarationSite,
            replace:
              declarationSite +
              '  if jq_match \'(.Module.Path // "") | test("(^|/)diene[._-]")\' "${go_manifest}"; then\n' +
              '    go_declared=true\n' +
              '  fi\n',
          });
          await repo.write('go.mod', goSelfModuleFixture);
          await repo.write('go-shim/go', selfModuleGoShim);
          const result = await repo.exec(
            `nix develop .#ci -c bash -c 'set -euo pipefail; chmod +x go-shim/go; export PATH="$PWD/go-shim:$PATH"; ./scripts/local/skills-sync.sh'`,
            { timeoutMs: 240000 },
          );
          if (result.exitCode === 0) {
            throw new Error('skills-sync stayed green after the main module became an external obligation');
          }
          const output = `${result.stdout}\n${result.stderr}`;
          if (!output.includes('Declared diene packages produced no vendored skills: go')) {
            throw new Error(`skills-sync failed for the wrong reason after the self-module sabotage:\n${output}`);
          }
        });
      },
    },
    {
      name: 'mutation-skills-sync-zero-skill-caught',
      description:
        'A focused sabotage must turn the skills-sync mechanism red: a declared diene dependency with nothing resolved and nothing committed must not publish an empty vendored tree.',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: any) {
        await withCleanProbeState(repo, probeCleanTargets, async () => {
          await removeCommittedVendor(repo);
          await repo.write('package.json', declaringPackageJson);
          await repo.write('go.mod', neutralGoModFixture);
          await repo.write('go-shim/go', neutralGoShim);
          await repo.write(`${keptSkill}.untracked`, 'untracked content is not a committed fallback\n');
          const result = await repo.exec(
            `nix develop .#ci -c bash -c 'set -euo pipefail; chmod +x go-shim/go; export PATH="$PWD/go-shim:$PATH"; ./scripts/local/skills-sync.sh'`,
            { timeoutMs: 240000 },
          );
          if (result.exitCode === 0) {
            throw new Error('skills-sync stayed green after a declared package produced no skills');
          }
          const output = `${result.stdout}\n${result.stderr}`;
          if (!output.includes('Declared diene packages produced no vendored skills: node')) {
            throw new Error(`skills-sync failed for the wrong reason after zero-skill resolution:\n${output}`);
          }
        });
      },
    },
    {
      name: 'mutation-skills-sync-go-transitive-mask-caught',
      description:
        'A focused sabotage must turn the skills-sync mechanism red: a matching module reached only transitively must not answer a direct root go.mod requirement that never resolved.',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: any) {
        await withCleanProbeState(repo, probeCleanTargets, async () => {
          await repo.write('go.mod', transitiveGoModFixture);
          await repo.write('go-shim/go', transitiveGoShim);
          await repo.write('go-fixture/skills/example/SKILL.md', 'transitive Go skill\n');
          const result = await repo.exec(
            `nix develop .#ci -c bash -c 'set -euo pipefail; chmod +x go-shim/go; export PATH="$PWD/go-shim:$PATH"; ./scripts/local/skills-sync.sh'`,
            { timeoutMs: 240000 },
          );
          if (result.exitCode === 0) {
            throw new Error(
              'skills-sync stayed green while a transitive module masked an unresolved direct requirement',
            );
          }
          const output = `${result.stdout}\n${result.stderr}`;
          if (!output.includes('Declared diene packages produced no vendored skills: go')) {
            throw new Error(`skills-sync failed for the wrong reason after the transitive-mask fixture:\n${output}`);
          }
        });
      },
    },
    {
      name: 'mutation-skills-sync-go-partial-direct-caught',
      description:
        'A focused sabotage must turn the skills-sync mechanism red: a direct root go.mod requirement that never resolved must be named, even when a sibling direct requirement staged skills of its own.',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: any) {
        await withCleanProbeState(repo, probeCleanTargets, async () => {
          await repo.write('go.mod', partialGoModFixture);
          await repo.write('go-shim/go', partialGoShim);
          await repo.write('go-fixture/skills/example/SKILL.md', 'resolved Go skill\n');
          const result = await repo.exec(
            `nix develop .#ci -c bash -c 'set -euo pipefail; chmod +x go-shim/go; export PATH="$PWD/go-shim:$PATH"; ./scripts/local/skills-sync.sh'`,
            { timeoutMs: 240000 },
          );
          if (result.exitCode === 0) {
            throw new Error('skills-sync stayed green while one direct diene requirement never resolved');
          }
          const output = `${result.stdout}\n${result.stderr}`;
          if (!output.includes('Directly required diene modules produced no vendored skills')) {
            throw new Error(`skills-sync failed for the wrong reason after the partial-resolution fixture:\n${output}`);
          }
          if (!output.includes(unresolvedGoModule)) {
            throw new Error(`skills-sync did not name the unresolved direct requirement:\n${output}`);
          }
          if (output.includes(`- ${resolvedGoModule}`)) {
            throw new Error(`skills-sync blamed the direct requirement that did resolve:\n${output}`);
          }
        });
      },
    },
    {
      name: 'mutation-skills-sync-pub-unresolved-caught',
      description:
        'A focused sabotage must turn the skills-sync mechanism red: a declared diene_ Pub dependency with no resolved package configuration must refuse instead of publishing a tree that silently omits it.',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: any) {
        await withCleanProbeState(repo, probeCleanTargets, async () => {
          await removeCommittedVendor(repo);
          await repo.write('pubspec.yaml', declaringPubspec);
          const result = await repo.exec(
            `nix develop .#ci -c bash -c 'set -euo pipefail; ./scripts/local/skills-sync.sh'`,
            { timeoutMs: 240000 },
          );
          if (result.exitCode === 0) {
            throw new Error('skills-sync stayed green after a declared Pub diene package produced no skills');
          }
          const output = `${result.stdout}\n${result.stderr}`;
          if (!output.includes('Declared diene packages produced no vendored skills: pub')) {
            throw new Error(`skills-sync failed for the wrong reason after an unresolved Pub declaration:\n${output}`);
          }
        });
      },
    },
    {
      name: 'mutation-skills-sync-malformed-json-caught',
      description:
        'A focused sabotage must turn the skills-sync mechanism red: each JSON manifest it validates must refuse by name, so a syntax error is not reported as an unexplained jq crash.',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: any) {
        await withCleanProbeState(repo, probeCleanTargets, async () => {
          const syncCommand = `nix develop .#ci -c bash -c 'set -euo pipefail; ./scripts/local/skills-sync.sh'`;
          const sites = [
            { path: 'package.json', content: malformedPackageJson },
            { path: '.dart_tool/package_config.json', content: malformedPackageConfig },
          ];
          for (const site of sites) {
            await repo.write(site.path, site.content);
            const result = await repo.exec(syncCommand, { timeoutMs: 240000 });
            if (result.exitCode === 0) {
              throw new Error(`skills-sync stayed green with a malformed ${site.path}`);
            }
            const output = `${result.stdout}\n${result.stderr}`;
            if (!output.includes(`${site.path} is not valid JSON`)) {
              throw new Error(`skills-sync did not name ${site.path} as the malformed manifest:\n${output}`);
            }
            const removed = await repo.exec(`rm -rf -- ${site.path}`);
            if (removed.exitCode !== 0) {
              throw new Error(
                `could not remove the malformed ${site.path} fixture: ${removed.stderr || removed.stdout}`,
              );
            }
          }
        });
      },
    },
  ],
};
