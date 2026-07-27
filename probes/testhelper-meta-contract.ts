import { expectGreen, expectRed } from './lib/helpers.ts';

// Gate: the meta tier (`scripts/ci/test.sh meta no-coverage`) exercises the
// shipped TestHelper's own assertions. Sabotage inverts the TestHelper's
// equality check so a passing case is treated as a failure, and proves the meta
// suite catches the broken contract.
export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  setup: {
    post: [
      'nix develop .#ci --no-write-lock-file -c dart pub get --offline || nix develop .#ci --no-write-lock-file -c dart pub get',
    ],
  },
  probes: [
    {
      name: 'baseline-testhelper-meta-contract-green',
      description: 'the meta suite passes against the pristine TestHelper',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(
          repo,
          'nix develop .#ci --no-write-lock-file -c ./scripts/ci/test.sh meta no-coverage',
          'testhelper-meta-contract',
        );
      },
    },
    {
      name: 'mutation-testhelper-meta-contract-caught',
      description: 'the meta suite fails once the TestHelper equality check is inverted',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: any) {
        const helpers = (await repo.glob('packages/*/lib/test_helper.dart')).sort();
        const target = helpers[0];
        if (!target) {
          throw new Error('testhelper-meta-contract: no lib/test_helper.dart to sabotage');
        }
        await repo.patch(target, { find: 'if (actual != expected) {', replace: 'if (actual == expected) {' });
        await expectRed(
          repo,
          'nix develop .#ci --no-write-lock-file -c ./scripts/ci/test.sh meta no-coverage',
          'testhelper-meta-contract',
        );
      },
    },
  ],
};
