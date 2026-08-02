import { ASSERTION_FLIPS, BUN_PROBE_SANDBOX, BUN_PROBE_SETUP } from './lib/bun.ts';
import { expectGreen, expectRedBecause } from './lib/helpers.ts';
import { flipAssertion } from './lib/mutations.ts';

const gate = 'nix develop --no-write-lock-file .#ci -c pls test:unit';

export default {
  contractVersion: 1,
  sandbox: BUN_PROBE_SANDBOX,
  setup: BUN_PROBE_SETUP,
  probes: [
    {
      name: 'baseline-bun-unit-tests-green',
      description: 'The unit suite runs through its own bunfig root and passes.',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(repo, gate, 'bun-unit-tests');
      },
    },
    {
      name: 'mutation-bun-unit-tests-caught',
      description: 'An inverted unit assertion must be refused as a failing test naming the mutated file.',
      kind: 'mutation',
      expectedImpact: ['bun-unit-coverage'],
      async run(repo: any) {
        const target = await flipAssertion(repo, {
          globs: ['tests/unit/**/*.test.ts'],
          replacements: ASSERTION_FLIPS,
        });
        // A red that never names the file we broke is a suite that collapsed for some other reason.
        await expectRedBecause(repo, gate, 'bun-unit-tests', ['(fail)', target.path]);
      },
    },
  ],
};
