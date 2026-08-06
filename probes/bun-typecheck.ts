import { expectBunGreen, expectBunRed } from './lib/bun-command.ts';

const command = "nix develop .#ci -c bash -lc './scripts/local/setup.sh && pre-commit run typecheck --all-files'";

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-bun-typecheck-green',
      description: 'The generated typecheck hook accepts the strict TypeScript source.',
      kind: 'baseline',
      async run(repo: any) {
        await expectBunGreen(repo, command, 'bun-typecheck');
      },
    },
    {
      name: 'mutation-bun-typecheck-caught',
      description: 'A TypeScript assignment error turns the typecheck hook red.',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: any) {
        const path = (await repo.glob('src/lib/**/*.ts')).sort()[0];
        if (!path) throw new Error('no TypeScript library source found');
        await repo.write(path, `${await repo.read(path)}\nconst probeTypeError: string = 1;\nvoid probeTypeError;\n`);
        await expectBunRed(repo, command, 'bun-typecheck');
      },
    },
  ],
};
