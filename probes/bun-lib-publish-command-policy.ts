import { defineGate } from './lib/definition.ts';
import { expectGreen, expectRed } from './lib/helpers.ts';

export default defineGate({
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  baseline: {
    name: 'baseline-bun-lib-publish-command-policy-green',
    description: 'The publish command requires public access and tolerate-republish behavior.',
    async run(repo: any) {
      await expectGreen(
        repo,
        'nix develop .#ci -c ./scripts/validate/bun-release-policy.sh command',
        'bun-lib-publish-command-policy',
      );
    },
  },
  mutation: {
    name: 'mutation-bun-lib-publish-command-policy-caught',
    description: 'Removing tolerate-republish turns command policy validation red.',
    expectedImpact: [],
    async run(repo: any) {
      await repo.patch('scripts/ci/publish.sh', {
        find: 'bun publish --access public --tolerate-republish',
        replace: 'bun publish --access public',
      });
      await expectRed(
        repo,
        'nix develop .#ci -c ./scripts/validate/bun-release-policy.sh command',
        'bun-lib-publish-command-policy',
      );
    },
  },
});
