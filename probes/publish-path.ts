import { expectBunGreen } from './lib/bun-command.ts';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-publish-path-green',
      description:
        'The API-key-authenticated bun publish --access public --tolerate-republish path is exercised via a dry run.',
      kind: 'baseline',
      async run(repo: any) {
        const version = JSON.parse(await repo.read('package.json')).version;
        await expectBunGreen(
          repo,
          `nix develop .#cd -c bash -lc 'NPM_API_KEY=probe-dummy GITHUB_REF_NAME=v${version} PUBLISH_DRY_RUN=1 ./scripts/ci/publish.sh'`,
          'publish-path',
        );
      },
    },
  ],
};
