import { expectGreen } from './lib/helpers.ts';

// Smoke: `dart pub publish --dry-run` completes cleanly, proving the package is
// packable and passes pub.dev's pre-publish validation.
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
      name: 'baseline-publish-dry-run-green',
      description: 'dart pub publish --dry-run succeeds on the pristine template',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(
          repo,
          "nix develop .#ci --no-write-lock-file -c bash -lc 'cd packages/diene_interfaces && dart pub publish --dry-run'",
          'publish-dry-run',
        );
      },
    },
  ],
};
