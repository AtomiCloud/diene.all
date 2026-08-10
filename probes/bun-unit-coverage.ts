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
      // DELIBERATE DIVERGENCE FROM THE PARENT - do not "restore" byte-identity.
      // This probe is byte-identical to bun-base upstream, so ownership-by-bytes would
      // put this declaration there. It CANNOT live there: the control it names does not
      // exist on bun-base, and declaring it would be a dangling reference inherited by
      // every descendant. Ruled by noel 2026-07-29 to declare on the leaf and record the
      // divergence. expectedImpact names FEATURES, features are PER-TEMPLATE, so a static
      // list in a shared file cannot be correct on all surfaces - the file was never truly
      // shared, only coincidentally identical. Upstream fix filed: sulfone.lite #23 /
      // PROBES.md Gap 6 (absent feature should resolve INAPPLICABLE, not dangling).
      // MEASURED: control output was 'eevee: Service is not ClusterIP' - it ran and failed.
      expectedImpact: ['garden-app-chart-render'],
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
