import { expectBunGreen, expectBunRed } from './lib/bun-command.ts';

const command =
  "nix develop .#ci -c bash -lc './scripts/local/setup.sh && pre-commit run a-deadcode-production --all-files'";

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-bun-deadcode-production-green',
      description: 'The production Knip hook accepts the runtime entry graph.',
      kind: 'baseline',
      async run(repo: any) {
        await expectBunGreen(repo, command, 'bun-deadcode-production');
      },
    },
    {
      name: 'mutation-bun-deadcode-production-caught',
      description: 'A source file used only by tests turns the production Knip hook red.',
      kind: 'mutation',
      expectedImpact: ['bun-unit-coverage'],
      async run(repo: any) {
        const testPath = (await repo.glob('tests/unit/**/*.test.ts')).sort()[0];
        if (!testPath) throw new Error('no unit test found for the test-only-use mutation');
        await repo.write('src/lib/__probe_test_only__.ts', 'export const probeTestOnly = (): number => 1;\n');
        await repo.write(
          testPath,
          `import { probeTestOnly } from '../../src/lib/__probe_test_only__';\n${await repo.read(testPath)}\nvoid probeTestOnly();\n`,
        );
        await expectBunRed(repo, command, 'bun-deadcode-production');
      },
    },
  ],
};
