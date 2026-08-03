import { breakAdapterRead, BUN_PROBE_SANDBOX, BUN_PROBE_SETUP } from './lib/bun.ts';
import { expectGreen, expectRedBecause } from './lib/helpers.ts';

const gate = 'nix develop --no-write-lock-file .#ci -c pls test:int';
// Testcontainers starts a real Redis, so the row needs a budget well above the shared default.
const budgetMs = 900000;

export default {
  contractVersion: 1,
  sandbox: BUN_PROBE_SANDBOX,
  setup: BUN_PROBE_SETUP,
  probes: [
    {
      name: 'baseline-bun-int-tests-green',
      description: 'The integration suite round-trips the adapter against a real containerized dependency.',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(repo, gate, 'bun-int-tests', { timeoutMs: budgetMs });
      },
    },
    {
      name: 'mutation-bun-int-tests-caught',
      description: 'An adapter read that stops reaching its client must be refused by the integration suite.',
      kind: 'mutation',
      expectedImpact: ['bun-int-coverage', 'bun-biome-lint'],
      async run(repo: any) {
        const target = await breakAdapterRead(repo);
        // A changed file is not the right changed file: assert where the fault landed.
        if (!target.path.startsWith('src/adapters/')) {
          throw new Error(`the integration sabotage landed outside the adapter tier: ${target.path}`);
        }
        await expectRedBecause(repo, gate, 'bun-int-tests', ['(fail)', 'tests/integration/'], {
          timeoutMs: budgetMs,
        });
      },
    },
  ],
};
