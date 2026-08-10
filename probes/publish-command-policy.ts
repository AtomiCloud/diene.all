import { expectGreen, expectRed } from './lib/helpers.ts';

const COMMAND = 'nix develop .#ci -c ./scripts/validate/publish-policy.sh command';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-publish-command-policy-green',
      description: 'The publish path uses the required public + tolerate-republish flags.',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(repo, COMMAND, 'publish-command-policy');
      },
    },
    {
      name: 'mutation-publish-command-policy-caught',
      description: 'Removing a required publish flag must redden the command policy.',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: any) {
        const script = 'scripts/ci/publish.sh';
        const source = await repo.read(script);
        await repo.write(script, source.replaceAll(' --tolerate-republish', ''));
        await expectRed(repo, COMMAND, 'publish-command-policy');
      },
    },
  ],
};
