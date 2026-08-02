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

const label = 'bun-unit-coverage';
const gate = 'nix develop --no-write-lock-file .#ci -c pls test:unit:coverage';
const ledger = 'coverage/unit/lcov.info';
const config = 'bunfig.unit.toml';
const scope = { label, scope: 'src/lib/', sourceGlob: 'src/lib/**/*.ts' };

export default {
  contractVersion: 1,
  sandbox: BUN_PROBE_SANDBOX,
  setup: BUN_PROBE_SETUP,
  probes: [
    {
      name: 'baseline-bun-unit-coverage-green',
      description: 'The unit ledger measures every domain file, nothing else, and clears its declared threshold.',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(repo, gate, label);
        const records = await readLcov(repo, ledger);
        await assertLedgerScope(repo, records, scope);
        assertAtLeast(records, (await readCoverageThreshold(repo, config, label)).effective, label);
      },
    },
    {
      name: 'mutation-bun-unit-coverage-caught',
      description: 'Uncovered domain lines must be refused by the threshold with every test still passing.',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: any) {
        await expectGreen(repo, gate, label);
        const before = await readLcov(repo, ledger);
        const threshold = await readCoverageThreshold(repo, config, label);
        await plantUncoveredLines(
          repo,
          before[0].file,
          'probeUncoveredDomain',
          uncoveredLinesNeeded(before, threshold.effective),
        );
        // A threshold refusal and a broken test both exit non-zero; only the reason separates them.
        await expectRedBecause(repo, gate, label, [' 0 fail'], { forbidden: ['(fail)'] });
        const after = await readLcov(repo, ledger);
        await assertLedgerScope(repo, after, scope);
        assertBelow(after, threshold.effective, label);
      },
    },
  ],
};
