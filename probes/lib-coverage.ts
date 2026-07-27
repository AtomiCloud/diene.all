import { expectBunGreen, expectBunRed } from './lib/bun-command.ts';
import { assertScopedLcov } from './lib/lcov.ts';

// Cost: medium (<3min) — the whole unit tier with coverage.
const command = 'nix develop .#ci -c ./scripts/ci/test.sh unit';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-lib-coverage-green',
      description: 'The domain tier is covered to 100% of lines and the ledger is scoped to src/lib only.',
      kind: 'baseline',
      async run(repo: any) {
        await expectBunGreen(repo, command, 'lib-coverage');
        await assertScopedLcov(repo, 'coverage/unit/lcov.info', 'src/lib/');
      },
    },
    {
      name: 'mutation-lib-coverage-caught',
      description: 'An uncovered exported domain function turns the domain coverage ledger red.',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: any) {
        // The ledger is only worth having if adding untested domain code fails the
        // build rather than quietly lowering the percentage.
        await repo.write(
          'src/lib/__probe_uncovered__/index.ts',
          'export const probeUncoveredLibFunction = (value: number): number => value * 2;\n',
        );
        await repo.write(
          'src/index.ts',
          `${await repo.read('src/index.ts')}\nexport { probeUncoveredLibFunction } from './lib/__probe_uncovered__';\n`,
        );
        await expectBunRed(repo, command, 'lib-coverage');
      },
    },
  ],
};
