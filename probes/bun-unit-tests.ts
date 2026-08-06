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
          "nix develop .#ci -c bash -lc './scripts/local/setup.sh && task test:unit'",
          'bun-unit-tests',
        );
      },
    },
    {
      name: 'mutation-bun-unit-tests-caught',
      description: 'A flipped should assertion turns the Bun unit tier red.',
      kind: 'mutation',
      expectedImpact: ['bun-unit-coverage'],
      async run(repo: any) {
        const paths = await repo.glob('tests/unit/**/*.test.ts');
        for (const path of paths) {
          const source = await repo.read(path);
          if (source.includes('should(actual).equal(expected);')) {
            await repo.write(
              path,
              source.replace('should(actual).equal(expected);', 'should(actual).not.equal(expected);'),
            );
            await expectBunRed(
              repo,
              "nix develop .#ci -c bash -lc './scripts/local/setup.sh && task test:unit'",
              'bun-unit-tests',
            );
            return;
          }
        }
        throw new Error('no structural should assertion target found');
      },
    },
  ],
};
