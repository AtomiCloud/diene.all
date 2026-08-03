import { BUN_PROBE_SANDBOX, BUN_PROBE_SETUP } from './lib/bun.ts';
import { expectGreen, expectRedBecause } from './lib/helpers.ts';

const gate = 'nix develop --no-write-lock-file .#ci -c pre-commit run a-deadcode-production --all-files';
const planted = 'src/lib/__probe_test_only__.ts';

export default {
  contractVersion: 1,
  sandbox: BUN_PROBE_SANDBOX,
  setup: BUN_PROBE_SETUP,
  probes: [
    {
      name: 'baseline-bun-knip-production-green',
      description: 'The blocking production Knip pass accepts the sample with only the public entry point.',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(repo, gate, 'bun-knip-production');
      },
    },
    {
      name: 'mutation-bun-knip-production-caught',
      description: 'A module reachable only from a test must be refused as an unused file by the production pass.',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: any) {
        const tests = (await repo.glob('tests/**/*.test.ts')).sort();
        if (tests.length === 0) {
          throw new Error('no test file found to give the planted module its test-only consumer');
        }
        // A scalar, not a function: the planted module lands in the unit ledger through the
        // all-files preload, and an uncalled function there would redden the coverage control too.
        await repo.write(planted, 'export const probeTestOnly = 1;\n');
        // From a TEST: a module nothing imports at all is unused under both configs and discriminates nothing.
        const test = tests[0];
        const relative = '../'.repeat(test.split('/').length - 1);
        await repo.write(
          test,
          `import { probeTestOnly } from '${relative}src/lib/__probe_test_only__';\n${await repo.read(test)}\nif (probeTestOnly < 0) throw new Error('probe fixture');\n`,
        );
        await expectRedBecause(repo, gate, 'bun-knip-production', ['Unused files', planted]);
      },
    },
  ],
};
