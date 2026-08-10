import { expectGreen } from './lib/helpers.ts';

// Smoke: the Dart toolchain the pipeline depends on (dart+flutter SDK, pana,
// dart_code_linter) is resolvable and runnable inside the dev shell.
//
// `gitlint --version` was removed from this assertion because gitlint is RETIRED,
// not because it was failing. The merge drops the binary from nix/packages.nix
// and nix/env.nix, `releaser lint-commit -c release.yaml` owns commit-message
// validation, and docs/standards/semantic-release states no .gitlint file may
// exist. Keeping the assertion would have reddened this smoke on a binary that is
// intentionally gone — an inventory expectation outliving the thing it inventories.
export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  setup: {
    post: [
      'nix develop .#ci --no-write-lock-file -c flutter pub get --offline || nix develop .#ci --no-write-lock-file -c flutter pub get',
    ],
  },
  probes: [
    {
      name: 'baseline-dart-tool-inventory-green',
      description: 'the Dart toolchain (dart, flutter, pana, dart_code_linter) is available',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(
          repo,
          'nix develop .#ci --no-write-lock-file -c bash -lc \'dart --version >/dev/null 2>&1 && cd packages/diene_e2e && dart pub global run pana --help 2>&1 | grep -qiE "usage|pana" && flutter pub run dart_code_linter:metrics --help >/dev/null 2>&1\'',
          'dart-tool-inventory',
        );
      },
    },
  ],
};
