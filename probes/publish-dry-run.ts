import { expectGreen } from './lib/helpers.ts';

// Smoke: the offline-safe archive-builder mode completes cleanly, proving the
// package is packable without advisory or pub.dev network access. Repository
// validators and the hermetic Pana gate own semantic validation separately.
export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  setup: {
    post: ['nix develop .#ci --no-write-lock-file -c dart pub get --offline'],
  },
  probes: [
    {
      name: 'baseline-publish-dry-run-green',
      description: 'dart pub publish builds the dry-run archive without remote validation',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(
          repo,
          "nix develop .#ci --no-write-lock-file -c bash -lc 'cd packages/diene_dart_lib && dart pub publish --dry-run --skip-validation'",
          'publish-dry-run',
        );
      },
    },
  ],
};
