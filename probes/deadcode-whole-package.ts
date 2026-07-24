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
        const sources = (await repo.glob('packages/*/lib/src/**/*.dart')).sort();
        const target = sources[0];
        if (!target) {
          throw new Error('deadcode-whole-package: no library source file to sabotage');
        }
        await repo.write(target, `${await repo.read(target)}\nint _probeDeadCode() => 1;\n`);
        await expectRed(repo, WHOLE_PASS, 'deadcode-whole-package');
      },
    },
  ],
};
