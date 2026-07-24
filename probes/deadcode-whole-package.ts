import { expectGreen, expectRed } from './lib/helpers.ts';

// Gate: the whole-package dead-code pass (`dart_code_linter` check-unused-code /
// check-unused-files over lib+test+example) forbids unreferenced declarations.
// Sabotage appends an unused private production member and proves the pass flags
// it as dead code.
const WHOLE_PASS =
  "nix develop .#ci --no-write-lock-file -c bash -lc 'cd packages/diene_dart_lib && dart run dart_code_linter:metrics check-unused-code lib test example && dart run dart_code_linter:metrics check-unused-files lib test example'";

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
      name: 'baseline-deadcode-whole-package-green',
      description: 'the whole-package dead-code pass is clean on the pristine template',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(repo, WHOLE_PASS, 'deadcode-whole-package');
      },
    },
    {
      name: 'mutation-deadcode-whole-package-caught',
      description: 'the whole-package dead-code pass flags an unused private member',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: any) {
        // dart_code_linter's check-unused-code does not flag unused top-level
        // functions, but check-unused-files flags an orphan library file. Drop an
        // orphan source under the member's lib/src that nothing references so the
        // whole-package pass (which chains check-unused-files) reddens.
        const members = (await repo.glob('packages/*/lib/src')).sort();
        const srcDir = members[0];
        if (!srcDir) {
          throw new Error('deadcode-whole-package: no member lib/src directory to sabotage');
        }
        await repo.write(`${srcDir}/__probe_dead_whole.dart`, 'int probeDeadWhole() => 1;\n');
        await expectRed(repo, WHOLE_PASS, 'deadcode-whole-package');
      },
    },
  ],
};
