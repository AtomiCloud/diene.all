import { expectBunGreen, expectBunRed } from './lib/bun-command.ts';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-bun-integration-tests-green',
      description: 'The Bun integration tier proves the Redis adapter with Testcontainers.',
      kind: 'baseline',
      async run(repo: any) {
        await expectBunGreen(
          repo,
          "nix develop .#ci -c bash -lc './scripts/local/setup.sh && pls test:int'",
          'bun-integration-tests',
        );
      },
    },
    {
      name: 'mutation-bun-integration-tests-caught',
      description: 'A broken adapter return turns the integration tier red.',
      kind: 'mutation',
      expectedImpact: ['bun-integration-coverage'],
      async run(repo: any) {
        const paths = await repo.glob('src/adapters/**/*.ts');
        for (const path of paths) {
          const source = await repo.read(path);
          if (source.includes('return this.client.get(key);')) {
            await repo.write(
              path,
              source.replace('return this.client.get(key);', 'return key.length === 0 ? this.client.get(key) : null;'),
            );
            await expectBunRed(
              repo,
              "nix develop .#ci -c bash -lc './scripts/local/setup.sh && pls test:int'",
              'bun-integration-tests',
            );
            return;
          }
        }
        throw new Error('no structural Redis adapter target found');
      },
    },
  ],
};
