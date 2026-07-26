import { expectGreen, expectRed } from './lib/helpers.ts';

// Gate: the unit test suite (`dart test test/unit`) guards library behavior.
// Sabotage flips a boolean matcher in the first unit test (falling back to an
// injected failing expectation) and proves the suite goes red.
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
      name: 'baseline-unit-tests-green',
      description: 'dart test test/unit passes on the pristine template',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(
          repo,
          "nix develop .#ci --no-write-lock-file -c bash -lc 'cd packages/diene_core_utils && dart test test/unit'",
          'unit-tests',
        );
      },
    },
    {
      name: 'mutation-unit-tests-caught',
      description: 'dart test test/unit fails once an assertion is inverted',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: any) {
        const tests = (await repo.glob('packages/*/test/unit/**/*.dart')).sort();
        const target = tests[0];
        if (!target) {
          throw new Error('unit-tests: no unit test file to sabotage');
        }
        const original = await repo.read(target);
        let mutated: string;
        if (original.includes(', isFalse)')) {
          mutated = original.replace(', isFalse)', ', isTrue)');
        } else if (original.includes(', isTrue)')) {
          mutated = original.replace(', isTrue)', ', isFalse)');
        } else {
          mutated = original.replace(
            'void main() {',
            "void main() {\n  test('probe sabotage', () {\n    expect(0, 1);\n  });",
          );
        }
        await repo.write(target, mutated);
        await expectRed(
          repo,
          "nix develop .#ci --no-write-lock-file -c bash -lc 'cd packages/diene_core_utils && dart test test/unit'",
          'unit-tests',
        );
      },
    },
  ],
};
