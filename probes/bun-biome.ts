import { expectBunGreen, expectBunRed } from './lib/bun-command.ts';

const command = "nix develop .#ci -c bash -lc './scripts/local/setup.sh && pre-commit run a-biome --all-files'";

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-bun-biome-green',
      description: 'The generated Biome lint hook accepts the TypeScript source.',
      kind: 'baseline',
      async run(repo: any) {
        await expectBunGreen(repo, command, 'bun-biome');
      },
    },
    {
      name: 'mutation-bun-biome-caught',
      description: 'A loose equality comparison turns the Biome lint hook red.',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: any) {
        const path = (await repo.glob('src/lib/**/*.ts')).sort()[0];
        if (!path) throw new Error('no TypeScript library source found');
        await repo.write(path, `${await repo.read(path)}\nconst probeBiome = 1;\nvoid (probeBiome == 1);\n`);
        await expectBunRed(repo, command, 'bun-biome');
      },
    },
  ],
};
