import { expectBunGreen, expectBunRed } from './lib/bun-command.ts';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-bun-unit-tests-green',
      description: 'The Bun unit tier passes through its Taskfile entry point.',
      kind: 'baseline',
      async run(repo: any) {
        await expectBunGreen(
          repo,
          "nix develop .#ci -c bash -lc './scripts/local/setup.sh && pls test:unit'",
          'bun-unit-tests',
        );
      },
    },
    {
      name: 'mutation-bun-unit-tests-caught',
      description: 'A flipped Result assertion turns the Bun unit tier red.',
      kind: 'mutation',
      expectedImpact: ['bun-unit-coverage'],
      async run(repo: any) {
        const path = 'tests/unit/api-engine.test.ts';
        const source = await repo.read(path);
        await repo.write(path, source.replace("toEqual(['ok', { id: 7 }])", "toEqual(['ok', { id: 8 }])"));
        await expectBunRed(
          repo,
          "nix develop .#ci -c bash -lc './scripts/local/setup.sh && pls test:unit'",
          'bun-unit-tests',
        );
      },
    },
  ],
};
