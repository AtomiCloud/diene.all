import { expectGreen, expectRedBecause } from './lib/helpers.ts';

const configPath = 'skills-sync.yaml';
const vendorDir = '.claude/skills/vendor';

const callPaths = [
  {
    name: 'setup',
    command: 'nix develop .#default -c task setup',
    declaration: ['Taskfile.yaml', 'skills-sync sync --tier setup'],
  },
  {
    name: 'pre-commit',
    command: 'nix develop .#ci -c pre-commit run a-skills-sync --all-files',
    declaration: ['nix/pre-commit.nix', '${packages.skills-sync}/bin/skills-sync sync --tier pre-commit'],
  },
  {
    name: 'ci',
    command: 'nix develop .#ci -c skills-sync sync --tier ci',
    declaration: ['.github/workflows/⚡reusable-precommit.yaml', 'skills-sync sync --tier ci'],
  },
] as const;

async function assertDeclaredWiring(repo: any): Promise<void> {
  const config = await repo.read(configPath);
  if (config !== 'schemaVersion: 1\nruntime: none\n') {
    throw new Error(`${configPath} must declare the workspace's explicit runtime: none opt-out`);
  }

  for (const callPath of callPaths) {
    const [path, invocation] = callPath.declaration;
    const source = await repo.read(path);
    if (!source.includes(invocation)) {
      throw new Error(`${callPath.name} skills-sync wiring is missing from ${path}: ${invocation}`);
    }
  }
}

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: callPaths.flatMap(callPath => [
    {
      name: `baseline-skills-sync-${callPath.name}-off-empty`,
      description: `The ${callPath.name} call path executes skills-sync and accepts the explicit off/empty workspace.`,
      kind: 'baseline' as const,
      async run(repo: any) {
        await assertDeclaredWiring(repo);
        await expectGreen(repo, callPath.command, 'skills-sync');
      },
    },
    {
      name: `mutation-skills-sync-${callPath.name}-vendored-content-caught`,
      description: `The ${callPath.name} call path refuses probe-owned vendored content while runtime is none.`,
      kind: 'mutation' as const,
      expectedImpact: [],
      async run(repo: any) {
        await assertDeclaredWiring(repo);
        const fixtureName = `probe-skills-sync-${callPath.name}.txt`;
        const fixturePath = `${vendorDir}/${fixtureName}`;
        const tracked = await repo.exec(`git ls-files --error-unmatch -- '${fixturePath}'`);
        if (tracked.exitCode === 0) {
          throw new Error(`${callPath.name} probe fixture must be owned by this arm, not tracked at ${fixturePath}`);
        }
        await repo.write(fixturePath, 'owned by the skills-sync probe\n');
        await expectRedBecause(repo, callPath.command, 'skills-sync', [
          'skills-sync names no runtime',
          `holds 1 vendored file(s): ${fixtureName}`,
          'A repository that vendors skills has a runtime',
        ]);
      },
    },
  ]),
};
