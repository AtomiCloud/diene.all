import { expectGreen } from './lib/helpers.ts';

// Smoke: the Dart toolchain the pipeline depends on (dart+flutter SDK, gitlint, pana,
// dart_code_linter) is resolvable and runnable inside the dev shell.
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
      description: 'the Dart toolchain (dart, flutter, gitlint, pana, dart_code_linter) is available',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(
          repo,
          'nix develop .#ci --no-write-lock-file -c bash -lc \'dart --version >/dev/null 2>&1 && gitlint --version >/dev/null 2>&1 && cd packages/diene_api_engine && dart pub global run pana --help 2>&1 | grep -qiE "usage|pana" && flutter pub run dart_code_linter:metrics --help >/dev/null 2>&1\'',
          'dart-tool-inventory',
        );
      },
    },
  ],
};
