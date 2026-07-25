import { expectBunGreen, expectBunRed } from './lib/bun-command.ts';

const TARGET = 'return Ok(response === ';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-bun-integration-tests-green',
      description: 'The Bun integration tier proves the store adapters with Testcontainers.',
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
        for (const path of paths.sort()) {
          const source = await repo.read(path);
          const index = source.indexOf(TARGET);
          if (index === -1) continue;
          const lineEnd = source.indexOf(';', index);
          const original = source.slice(index, lineEnd + 1);
          await repo.write(path, source.replace(original, 'return Ok(false);'));
          await expectBunRed(
            repo,
            "nix develop .#ci -c bash -lc './scripts/local/setup.sh && pls test:int'",
            'bun-integration-tests',
          );
          return;
        }
        throw new Error('no structural adapter success return found');
      },
    },
  ],
};
