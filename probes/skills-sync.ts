import { expectGreen, expectRedBecause } from './lib/helpers.ts';

const configPath = 'skills-sync.yaml';

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

async function assertDeclaredWiring(repo: any): Promise<string> {
  const config = await repo.read(configPath);
  const runtime = /^runtime:\s*([^\s#]+)\s*$/m.exec(config)?.[1];
  if (!runtime) {
    throw new Error(`${configPath} must declare a runtime`);
  }

  for (const callPath of callPaths) {
    const [path, invocation] = callPath.declaration;
    const source = await repo.read(path);
    if (!source.includes(invocation)) {
      throw new Error(`${callPath.name} skills-sync wiring is missing from ${path}: ${invocation}`);
    }
  }

  return runtime;
}

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: callPaths.flatMap(callPath => [
    {
      name: `baseline-skills-sync-${callPath.name}-off-empty`,
      description: `The ${callPath.name} call path executes skills-sync with the runtime declared by its configuration.`,
      kind: 'baseline' as const,
      async run(repo: any) {
        const runtime = await assertDeclaredWiring(repo);
        await expectGreen(repo, callPath.command, `skills-sync (${runtime})`);
      },
    },
    {
      name: `mutation-skills-sync-${callPath.name}-wrong-runtime-caught`,
      description: `The ${callPath.name} call path refuses an explicit opt-out when the repository already vendors skills.`,
      kind: 'mutation' as const,
      expectedImpact: [],
      async run(repo: any) {
        const runtime = await assertDeclaredWiring(repo);
        if (runtime === 'none') {
          throw new Error(`${configPath} must name an active runtime before this wrong-runtime mutation can differ`);
        }
        await repo.write(configPath, `schemaVersion: 1\nruntime: none\n`);
        await expectRedBecause(repo, callPath.command, 'skills-sync', [
          'skills-sync names no runtime',
          'A repository that vendors skills has a runtime',
        ]);
      },
    },
  ]),
};
