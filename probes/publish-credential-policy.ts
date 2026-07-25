import { expectGreen, expectRed } from './lib/helpers.ts';

const CREDENTIAL = 'nix develop .#ci -c ./scripts/validate/publish-policy.sh credential';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-publish-credential-policy-green',
      description: 'The reusable publish workflow forwards the required NPM_API_KEY secret.',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(repo, CREDENTIAL, 'publish-credential-policy');
      },
    },
    {
      name: 'mutation-publish-credential-policy-caught',
      description: 'Disconnecting the NPM_API_KEY forwarding must redden the credential policy.',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: any) {
        const workflow = '.github/workflows/⚡reusable-publish.yaml';
        const source = await repo.read(workflow);
        await repo.write(workflow, source.replace('NPM_API_KEY: ${{ secrets.NPM_API_KEY }}', 'NODE_ENV: production'));
        await expectRed(repo, CREDENTIAL, 'publish-credential-policy');
      },
    },
  ],
};
