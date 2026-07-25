import { expectBunGreen } from './lib/bun-command.ts';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-bun-build-green',
      description: 'The Bun build task produces the bundle derived from package.json .bin.',
      kind: 'baseline',
      async run(repo: any) {
        await expectBunGreen(repo, "nix develop .#ci -c bash -lc './scripts/local/setup.sh && pls build'", 'bun-build');
        if ((await repo.glob('dist/bun-cli.js')).length !== 1) throw new Error('dist/bun-cli.js is missing');
      },
    },
  ],
};
