import { expectGreen, expectRed } from './lib/helpers.ts';

// Gate: `pana --exit-code-threshold 0` requires a perfect pub.dev package score.
// Sabotage comments out the member `description:` (a scored metadata field) and
// proves pana docks points and fails the threshold.
const PANA =
  "nix develop .#ci --no-write-lock-file -c bash -lc 'cd packages/diene_auth_engine && dart pub global run pana --exit-code-threshold 0 .'";

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  setup: {
    post: [
      'nix develop .#ci --no-write-lock-file -c flutter pub get --offline || nix develop .#ci --no-write-lock-file -c flutter pub get',
      // pana is not (and cannot be) a dev_dependency of this Flutter member —
      // it is unsolvable against flutter_test's SDK pins inside the shared pub
      // workspace resolution. Activate it into its own isolated resolution.
      'nix develop .#ci --no-write-lock-file -c dart pub global activate --overwrite pana 0.23.14',
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
        await repo.patch('packages/diene_auth_engine/pubspec.yaml', {
          find: 'description:',
          replace: '#description:',
        });
        await expectRed(repo, PANA, 'pana-score');
      },
    },
  ],
};
