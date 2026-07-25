import { expectGreen, expectRed } from './lib/helpers.ts';

// Gate: `pana --exit-code-threshold 0` requires a perfect pub.dev package score.
// Sabotage comments out the member `description:` (a scored metadata field) and
// proves pana docks points and fails the threshold.
const PANA =
  "nix develop .#ci --no-write-lock-file -c bash -lc 'cd packages/diene_interfaces && dart run pana --exit-code-threshold 0 .'";

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
      name: 'baseline-pana-score-green',
      description: 'pana reports a perfect score on the pristine template',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(repo, PANA, 'pana-score');
      },
    },
    {
      name: 'mutation-pana-score-caught',
      description: 'pana fails the threshold once the package description is removed',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: any) {
        await repo.patch('packages/diene_interfaces/pubspec.yaml', {
          find: 'description:',
          replace: '#description:',
        });
        await expectRed(repo, PANA, 'pana-score');
      },
    },
  ],
};
