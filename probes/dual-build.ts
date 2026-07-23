import { expectBunGreen } from './lib/bun-command.ts';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-dual-build-green',
      description: 'pls build emits ESM, CJS, .d.ts, and a byte-identical .d.cts (D7).',
      kind: 'baseline',
      async run(repo: any) {
        await expectBunGreen(
          repo,
          "nix develop .#ci -c bash -lc './scripts/local/setup.sh && pls build'",
          'dual-build',
        );
        for (const artifact of ['dist/index.js', 'dist/index.cjs', 'dist/index.d.ts', 'dist/index.d.cts']) {
          if ((await repo.glob(artifact)).length !== 1) {
            throw new Error(`missing build artifact: ${artifact}`);
          }
        }
        const dts = await repo.read('dist/index.d.ts');
        const dcts = await repo.read('dist/index.d.cts');
        if (dts !== dcts) {
          throw new Error('.d.cts is not a byte-copy of .d.ts');
        }
      },
    },
  ],
};
