import { expectBunGreen, expectBunRed } from './lib/bun-command.ts';

const PUBLINT = 'nix develop .#ci -c ./scripts/ci/pkg-validate.sh publint';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-publint-green',
      description: 'publint --strict validates the packed package shape.',
      kind: 'baseline',
      async run(repo: any) {
        await expectBunGreen(repo, PUBLINT, 'publint');
      },
    },
    {
      name: 'mutation-publint-caught',
      description: 'Pointing an export at a missing file must redden publint.',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: any) {
        const manifest = JSON.parse(await repo.read('package.json'));
        manifest.exports['.'].import.default = './dist/__probe_missing__.js';
        await repo.write('package.json', `${JSON.stringify(manifest, null, 2)}\n`);
        await expectBunRed(repo, PUBLINT, 'publint');
      },
    },
  ],
};
