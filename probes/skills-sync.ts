import { expectGreen } from './lib/helpers.ts';

const goModFixture = 'module example.com/app\n\ngo 1.22\n\nrequire diene.example.com/go-core v0.1.0\n';

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

const declaringPackageJson = `${JSON.stringify(
  {
    name: 'skills-sync-fixture',
    private: true,
    dependencies: { '@atomicloud/diene.absent': '1.0.0' },
  },
  null,
  2,
)}\n`;

const keptSkill = '.claude/skills/vendor/diene.kept/example/SKILL.md';
const probeCleanTargets = [
  '.claude/skills/vendor',
  'node_modules/@atomicloud/diene.readonly',
  'node_modules/@atomicloud/diene.untracked',
  'package.json',
  'go.mod',
  'go-shim',
].join(' ');

async function restoreProbeState(repo: any): Promise<void> {
  const restored = await repo.exec('git restore --source=HEAD --staged --worktree -- .');
  if (restored.exitCode !== 0) {
    throw new Error(`could not restore tracked probe state: ${restored.stderr || restored.stdout}`);
  }
  const cleaned = await repo.exec(`git clean -fdx -- ${probeCleanTargets}`);
  if (cleaned.exitCode !== 0) {
    throw new Error(`could not remove untracked probe fixtures: ${cleaned.stderr || cleaned.stdout}`);
  }
}

async function withCleanProbeState(repo: any, body: () => Promise<void>): Promise<void> {
  await restoreProbeState(repo);
  try {
    await body();
  } finally {
    await restoreProbeState(repo);
  }
}

async function stageKeptSkill(repo: any): Promise<void> {
  await repo.write(keptSkill, 'committed skill\n');
  const staged = await repo.exec(`git add ${keptSkill}`);
  if (staged.exitCode !== 0) {
    throw new Error(`could not stage the committed vendored skill: ${staged.stderr || staged.stdout}`);
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
        await withCleanProbeState(repo, async () => {
          await repo.write('.claude/skills/vendor/stale/SKILL.md', 'stale\n');
          await expectGreen(
            repo,
            `nix develop .#ci -c bash -c 'set -euo pipefail; first="$(mktemp -d)"; second="$(mktemp -d)"; readonly_skill="node_modules/@atomicloud/diene.readonly/skills/example"; trap "rm -rf \\"$first\\" \\"$second\\"" EXIT; mkdir -p "$readonly_skill"; printf "readonly skill\\n" >"$readonly_skill/SKILL.md"; chmod -R a-w node_modules/@atomicloud/diene.readonly .claude/skills/vendor/stale; ./scripts/local/skills-sync.sh; test ! -e .claude/skills/vendor/stale; test -f .claude/skills/vendor/diene.readonly/example/SKILL.md; jq -e ". == [\\"diene.readonly/example/SKILL.md\\"]" .claude/skills/vendor/manifest.json >/dev/null; cp -R .claude/skills/vendor/. "$first"/; ./scripts/local/skills-sync.sh; cp -R .claude/skills/vendor/. "$second"/; diff -ru "$first" "$second"'`,
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
        await withCleanProbeState(repo, async () => {
          await repo.write('package.json', declaringPackageJson);
          await stageKeptSkill(repo);
          await expectGreen(
            repo,
            `nix develop .#ci -c bash -c 'set -euo pipefail; ./scripts/local/skills-sync.sh; test "$(cat ${keptSkill})" = "committed skill"'`,
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
        await withCleanProbeState(repo, async () => {
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
      name: 'mutation-skills-sync-broken-go-caught',
      description:
        'A focused sabotage must turn the skills-sync mechanism red: a failing go module listing must fail the sync outright, even with committed vendored skills that could have been preserved.',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: any) {
        await withCleanProbeState(repo, async () => {
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
      name: 'mutation-skills-sync-zero-skill-caught',
      description:
        'A focused sabotage must turn the skills-sync mechanism red: a declared diene dependency with nothing resolved and nothing committed must not publish an empty vendored tree.',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: any) {
        await withCleanProbeState(repo, async () => {
          await repo.write('package.json', declaringPackageJson);
          await repo.write(`${keptSkill}.untracked`, 'untracked content is not a committed fallback\n');
          const result = await repo.exec('nix develop .#ci -c ./scripts/local/skills-sync.sh', {
            timeoutMs: 240000,
          });
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
  ],
};
