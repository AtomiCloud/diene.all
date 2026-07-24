import { expectBunGreen, expectBunRed } from './lib/bun-command.ts';

const command = "nix develop .#ci -c bash -lc './scripts/local/setup.sh && pre-commit run a-deadcode --all-files'";

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-bun-deadcode-green',
      description: 'The strict repository Knip hook accepts the complete source and tests.',
      kind: 'baseline',
      async run(repo: any) {
        await expectBunGreen(repo, command, 'bun-deadcode');
      },
    },
    {
      name: 'mutation-bun-deadcode-caught',
      description: 'An unused exported library member turns the repository Knip hook red.',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: any) {
        const entrySource = await repo.read('src/index.ts');
        const path = (await repo.glob('src/lib/**/*.ts')).sort().find((candidate: string) => {
          const modulePath = `./${candidate.replace(/^src\//, '').replace(/\.ts$/, '')}`;
          return !entrySource.includes(modulePath);
        });
        if (!path) throw new Error('no internal TypeScript library source found');
        await repo.write(path, `${await repo.read(path)}\nexport const probeDead = 1;\n`);
        await expectBunRed(repo, command, 'bun-deadcode');
      },
    },
  ],
};
