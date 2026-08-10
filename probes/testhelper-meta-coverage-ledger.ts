import { expectGreen, expectRed, preserveMutationBeforeRestore } from './lib/helpers.ts';

// Gate: `scripts/ci/test.sh meta coverage` enforces a 100% line-coverage ledger
// scoped to `lib/test_helper.dart`. Sabotage appends an uncovered helper
// function and proves the meta coverage ledger falls below 100% and fails.
export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  setup: {
    post: ['nix develop .#ci --no-write-lock-file -c dart pub get --offline'],
  },
  probes: [
    {
      name: 'baseline-testhelper-meta-coverage-ledger-green',
      description: 'the meta coverage ledger holds at 100% on the pristine TestHelper',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(
          repo,
          'nix develop .#ci --no-write-lock-file -c ./scripts/ci/test.sh meta coverage',
          'testhelper-meta-coverage-ledger',
        );
      },
    },
    {
      name: 'mutation-testhelper-meta-coverage-ledger-caught',
      description: 'the meta coverage ledger fails when an uncovered helper function is added',
      kind: 'mutation',
      expectedImpact: ['deadcode-whole-package'],
      async run(repo: any) {
        const helpers = (await repo.glob('packages/*/lib/test_helper.dart')).sort();
        const target = helpers[0];
        if (!target) {
          throw new Error('testhelper-meta-coverage-ledger: no lib/test_helper.dart to sabotage');
        }
        const original = await repo.read(target);
        try {
          await repo.write(target, `${original}\nint probeUncoveredHelper() {\n  return 1;\n}\n`);
          await expectRed(
            repo,
            'nix develop .#ci --no-write-lock-file -c ./scripts/ci/test.sh meta coverage',
            'testhelper-meta-coverage-ledger',
          );
        } finally {
          await preserveMutationBeforeRestore(repo, 'testhelper-meta-coverage-ledger', target, original);
        }
      },
    },
  ],
};
