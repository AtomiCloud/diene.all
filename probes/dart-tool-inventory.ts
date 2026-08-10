import { expectGreen } from './lib/helpers.ts';

// Smoke: the Dart toolchain the pipeline depends on (dart SDK, pana, coverage,
// dart_code_linter) is resolvable and runnable inside the dev shell.
//
// gitlint was RETIRED by the parent merge and its assertion was removed with it,
// not before it: gitlint is gone from nix/env.nix and nix/packages.nix, and
// releaser lint-commit -c release.yaml is now the commit-message gate. An
// inventory that still demanded a deliberately absent binary would go red on the
// retirement itself.
export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  setup: {
    post: ['nix develop .#ci --no-write-lock-file -c dart pub get --offline'],
  },
  probes: [
    {
      name: 'baseline-dart-tool-inventory-green',
      description: 'the Dart toolchain (dart, pana, coverage, dart_code_linter) is available',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(
          repo,
          'nix develop .#ci --no-write-lock-file -c bash -lc \'dart --version >/dev/null 2>&1 && cd packages/diene_config && dart run pana --help 2>&1 | grep -qiE "usage|pana" && dart run coverage:format_coverage --help >/dev/null 2>&1 && dart run dart_code_linter:metrics --help >/dev/null 2>&1\'',
          'dart-tool-inventory',
        );
      },
    },
  ],
};
