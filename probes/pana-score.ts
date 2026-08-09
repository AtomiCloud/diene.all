import { expectGreen, expectRed } from './lib/helpers.ts';

// Gate: the SDK must generate API docs, then
// `pana --no-dartdoc --exit-code-threshold 0` requires a perfect score from
// every remaining hermetic Pana category. Pana's own Dartdoc integration is
// excluded because it invokes the current SDK with an unsupported
// `--sanitize-html` flag; the direct `dart doc --dry-run` retains that coverage.
// Sabotage comments out the member `description:` (a scored metadata field) and
// proves pana docks points and fails the threshold.
const PANA =
  "nix develop .#ci --no-write-lock-file -c bash -lc 'cd packages/diene_dart_lib && dart doc --dry-run && dart run pana --no-dartdoc --exit-code-threshold 0 .'";

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  setup: {
    post: ['nix develop .#ci --no-write-lock-file -c dart pub get --offline'],
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
        await repo.patch('packages/diene_dart_lib/pubspec.yaml', {
          find: 'description:',
          replace: '#description:',
        });
        await expectRed(repo, PANA, 'pana-score');
      },
    },
  ],
};
