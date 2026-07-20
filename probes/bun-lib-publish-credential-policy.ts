import { defineGate } from './lib/definition.ts';
import { expectGreen, expectRed } from './lib/helpers.ts';

export default defineGate({
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  baseline: {
    name: 'baseline-bun-lib-publish-credential-policy-green',
    description: 'The reusable publish path requires and forwards the real NPM_API_KEY secret.',
    async run(repo: any) {
      await expectGreen(
        repo,
        'nix develop .#ci -c ./scripts/validate/bun-release-policy.sh credential',
        'bun-lib-publish-credential-policy',
      );
    },
  },
  mutation: {
    name: 'mutation-bun-lib-publish-credential-policy-caught',
    description: 'Disconnecting the required org secret turns credential policy validation red.',
    expectedImpact: [],
    async run(repo: any) {
      await repo.patch('.github/workflows/⚡reusable-publish.yaml', {
        find: 'NPM_API_KEY: ${{ secrets.NPM_API_KEY }}',
        replace: 'NPM_API_KEY: disconnected',
      });
      await expectRed(
        repo,
        'nix develop .#ci -c ./scripts/validate/bun-release-policy.sh credential',
        'bun-lib-publish-credential-policy',
      );
    },
  },
});
