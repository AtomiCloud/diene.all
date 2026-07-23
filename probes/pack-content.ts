import { expectBunGreen, expectBunRed } from './lib/bun-command.ts';

const CONTENT = 'nix develop .#ci -c ./scripts/ci/pkg-validate.sh content';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-pack-content-green',
      description: 'The packed tarball carries every declared dist artifact and the usage skill.',
      kind: 'baseline',
      async run(repo: any) {
        await expectBunGreen(repo, CONTENT, 'pack-content');
      },
    },
    {
      name: 'mutation-pack-content-caught',
      description: 'Dropping a path from the package allowlist must redden the pack-content check.',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: any) {
        const manifest = JSON.parse(await repo.read('package.json'));
        manifest.files = ['dist'];
        await repo.write('package.json', `${JSON.stringify(manifest, null, 2)}\n`);
        await expectBunRed(repo, CONTENT, 'pack-content');
      },
    },
  ],
};
