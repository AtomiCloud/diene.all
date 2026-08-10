import { expectBunGreen, expectBunRed } from './lib/bun-command.ts';

const command = 'nix develop .#ci -c ./scripts/ci/test.sh meta';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-bun-meta-testhelper-green',
      description: 'The packaged TestHelper meta contract passes with its dedicated coverage ledger.',
      kind: 'baseline',
      async run(repo: any) {
        await expectBunGreen(repo, command, 'bun-meta-conditional');
        if ((await repo.glob('coverage/meta/lcov.info')).length !== 1) {
          throw new Error('TestHelper meta tier must emit its dedicated coverage artifact');
        }
      },
    },
    {
      name: 'mutation-bun-meta-conditional-caught',
      description: 'An activated TestHelper meta test with a failing assertion must redden the meta tier.',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: any) {
        await repo.write('src/test-helper/probe.ts', 'export function probeMetaValue(): number {\n  return 1;\n}\n');
        await repo.write(
          'tests/meta/conditional.test.ts',
          [
            "import { expect, test } from 'bun:test';",
            "import { probeMetaValue } from '../../src/test-helper/probe';",
            '',
            "test('meta conditional sabotage fails', () => {",
            '  expect(probeMetaValue()).toBe(2);',
            '});',
            '',
          ].join('\n'),
        );
        await expectBunRed(repo, command, 'bun-meta-conditional');
      },
    },
  ],
};
