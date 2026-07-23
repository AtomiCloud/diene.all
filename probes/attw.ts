import { expectBunGreen, expectBunRed } from './lib/bun-command.ts';

const ATTW = 'nix develop .#ci -c ./scripts/ci/pkg-validate.sh attw';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-attw-green',
      description: 'attw independently validates import/require type resolution.',
      kind: 'baseline',
      async run(repo: any) {
        await expectBunGreen(repo, ATTW, 'attw');
      },
    },
    {
      name: 'mutation-attw-caught',
      description: 'Mapping require.types to the wrong declaration kind must redden attw.',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: any) {
        const manifest = JSON.parse(await repo.read('package.json'));
        // The CJS require condition must resolve to the .d.cts declaration; point
        // it at the ESM .d.ts so attw reports the masquerade.
        manifest.exports['.'].require.types = './dist/index.d.ts';
        await repo.write('package.json', `${JSON.stringify(manifest, null, 2)}\n`);
        await expectBunRed(repo, ATTW, 'attw');
      },
    },
  ],
};
