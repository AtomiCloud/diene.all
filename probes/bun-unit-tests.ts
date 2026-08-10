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
      // DELIBERATE DIVERGENCE FROM THE PARENT - do not "restore" byte-identity.
      // Byte-identical to bun-base upstream, but the control named below does not exist
      // there; declaring it upstream would be a dangling reference inherited by every
      // descendant. Ruled by noel 2026-07-29. Upstream fix: sulfone.lite #23 / Gap 6.
      //
      // EVIDENCE IS WEAKER FOR lib-coverage THAN FOR THE OTHER FOUR AND I AM MARKING IT:
      // the 6f5907a matrix recorded control_failed naming lib-coverage, but its captured
      // control output was EMPTY, so unlike the sibling rows there is no per-control text
      // proving what failed. The verdict is real; the corroboration is not. If a later run
      // shows this control green, drop lib-coverage rather than defending it.
      expectedImpact: ['bun-unit-coverage', 'lib-coverage'],
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
