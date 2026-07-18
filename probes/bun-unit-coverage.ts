import { expectBunGreen, expectBunRed } from './lib/bun-command.ts';
import { assertScopedLcov } from './lib/lcov.ts';

const command = 'nix develop .#ci -c ./scripts/ci/test.sh unit';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-bun-unit-coverage-green',
      description: 'Unit coverage is complete and scoped only to src/lib.',
      kind: 'baseline',
      async run(repo: any) {
        await expectBunGreen(repo, command, 'bun-unit-coverage');
        await assertScopedLcov(repo, 'coverage/unit/lcov.info', 'src/lib/');
      },
    },
    {
      name: 'mutation-bun-unit-coverage-caught',
      description: 'An uncovered library source file turns the unit coverage ledger red.',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: any) {
        await repo.write('src/lib/__probe_uncovered__.ts', 'export const probeUncovered = (): number => 1;\n');
        await repo.write(
          'src/index.ts',
          `${await repo.read('src/index.ts')}\nexport { probeUncovered } from './lib/__probe_uncovered__';\n`,
        );
        await expectBunRed(repo, command, 'bun-unit-coverage');
      },
    },
  ],
};
