import {
  assertAtLeast,
  assertBelow,
  assertLedgerScope,
  BUN_PROBE_SANDBOX,
  BUN_PROBE_SETUP,
  plantUncoveredLines,
  readCoverageThreshold,
  readLcov,
  uncoveredLinesNeeded,
} from './lib/bun.ts';
import { expectGreen, expectRedBecause } from './lib/helpers.ts';

const label = 'bun-int-coverage';
const gate = 'nix develop --no-write-lock-file .#ci -c pls test:int:coverage';
const ledger = 'coverage/int/lcov.info';
const config = 'bunfig.int.toml';
const scope = { label, scope: 'src/adapters/', sourceGlob: 'src/adapters/**/*.ts' };
// Two container-backed runs in the mutation arm, so the row carries its own budget.
const budgetMs = 900000;

export default {
  contractVersion: 1,
  sandbox: BUN_PROBE_SANDBOX,
  setup: BUN_PROBE_SETUP,
  probes: [
    {
      name: 'baseline-bun-int-coverage-green',
      description: 'The integration ledger measures every adapter, nothing else, and clears its declared threshold.',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(repo, gate, label, { timeoutMs: budgetMs });
        const records = await readLcov(repo, ledger);
        await assertLedgerScope(repo, records, scope);
        assertAtLeast(records, (await readCoverageThreshold(repo, config, label)).effective, label);
      },
    },
    {
      name: 'mutation-bun-int-coverage-caught',
      description: 'Uncovered adapter lines must be refused by the threshold with every test still passing.',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: any) {
        await expectGreen(repo, gate, label, { timeoutMs: budgetMs });
        const before = await readLcov(repo, ledger);
        const threshold = await readCoverageThreshold(repo, config, label);
        await plantUncoveredLines(
          repo,
          before[0].file,
          'probeUncoveredAdapter',
          uncoveredLinesNeeded(before, threshold.effective),
        );
        // A threshold refusal and a broken test both exit non-zero; only the reason separates them.
        await expectRedBecause(repo, gate, label, [' 0 fail'], { forbidden: ['(fail)'], timeoutMs: budgetMs });
        const after = await readLcov(repo, ledger);
        await assertLedgerScope(repo, after, scope);
        assertBelow(after, threshold.effective, label);
      },
    },
  ],
};
