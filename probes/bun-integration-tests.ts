import { expectBunGreen, expectBunRed } from './lib/bun-command.ts';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-bun-integration-tests-green',
      description: 'The Bun integration tier proves reconciliation against a real local HTTP server.',
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
      description: 'A changed real-server fixture turns the integration tier red.',
      kind: 'mutation',
      expectedImpact: ['bun-integration-coverage'],
      async run(repo: any) {
        const path = 'tests/integration/http-contract.test.ts';
        const source = await repo.read(path);
        await repo.write(path, source.replace("source: 'real-server'", "source: 'mutated-server'"));
        await expectBunRed(
          repo,
          "nix develop .#ci -c bash -lc './scripts/local/setup.sh && pls test:int'",
          'bun-integration-tests',
        );
      },
    },
  ],
};
