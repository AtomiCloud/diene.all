import { BUN_PROBE_SANDBOX, BUN_PROBE_SETUP, plantDeadExport } from './lib/bun.ts';
import { expectGreen, expectRedBecause } from './lib/helpers.ts';

const gate = 'nix develop --no-write-lock-file .#ci -c pre-commit run a-deadcode --all-files';

export default {
  contractVersion: 1,
  sandbox: BUN_PROBE_SANDBOX,
  setup: BUN_PROBE_SETUP,
  probes: [
    {
      name: 'baseline-bun-knip-repository-green',
      description: 'The blocking repository Knip pass accepts the sample with source and tests as entry points.',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(repo, gate, 'bun-knip-repository');
      },
    },
    {
      name: 'mutation-bun-knip-repository-caught',
      description: 'A dead export must be refused as an unused export naming the symbol, not merely fail.',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: any) {
        const target = await plantDeadExport(repo, { symbol: 'probeDeadExport' });
        await expectRedBecause(repo, gate, 'bun-knip-repository', ['Unused exports', 'probeDeadExport', target.path]);
      },
    },
  ],
};
