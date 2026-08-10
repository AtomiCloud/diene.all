import { expectGreen, expectRed } from './lib/helpers.ts';

const TAG = 'nix develop .#ci -c ./scripts/validate/publish-policy.sh tag';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-publish-tag-policy-green',
      description: 'CD triggers on the release tag pattern v*.*.*.',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(repo, TAG, 'publish-tag-policy');
      },
    },
    {
      name: 'mutation-publish-tag-policy-caught',
      description: 'A non-release trigger pattern must redden the tag policy.',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: any) {
        const workflow = '.github/workflows/cd.yaml';
        const source = await repo.read(workflow);
        await repo.write(workflow, source.replace('v*.*.*', 'release-*'));
        await expectRed(repo, TAG, 'publish-tag-policy');
      },
    },
  ],
};
