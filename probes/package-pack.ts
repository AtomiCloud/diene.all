import { expectBunGreen } from './lib/bun-command.ts';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-package-pack-green',
      description: 'bun pm pack produces a non-empty installable tarball for the validators.',
      kind: 'baseline',
      async run(repo: any) {
        await expectBunGreen(
          repo,
          "nix develop .#ci -c bash -lc './scripts/local/setup.sh && ./scripts/ci/build.sh && bun pm pack --filename pkg.tgz && test -s pkg.tgz'",
          'package-pack',
        );
        if ((await repo.glob('pkg.tgz')).length !== 1) {
          throw new Error('pkg.tgz was not produced');
        }
      },
    },
  ],
};
